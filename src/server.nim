import std/[
  tables,
  hashes,
  sets,
  oids,
  random,
  unicode,
]

import happyx
import happyx/core/constants

import results


{.experimental: "inferGenericTypes".}


# TODO: use actual cryptographic stuff
# TODO: Prevent race conditions
# TODO: Replace Oid with a snowflake/token depending on usage
# TODO: Message encryption?
type
  PublicName = distinct string

  AccountId = distinct Oid
  AccountAuthToken = distinct Oid
  Account = ref object
    accountId: AccountId
    identities: seq[Identity]
    isDeleted: bool

  PostId = distinct Oid
  Post = ref object
    postId: PostId
    author: Identity
    contents: string

  ChannelId = distinct Oid
  Channel = ref object
    channelId: ChannelId
    name: PublicName
    posts: seq[Post]

  # TODO: Add another layer for Identity + CommunityMember to support nicknames
  IdentityId = distinct Oid
  Identity = ref object
    identityId: IdentityId
    name: PublicName
    sourceAccount: Account # not exposed through the public api
    memberOf: seq[Community] # exposed to source account, hidden from community view

  CommunityId = distinct Oid
  Community = ref object
    communityId: CommunityId
    name: PublicName
    owner: Identity
    members: seq[Identity]
    channels: seq[Channel]

  PermissionHandle = object
    ## For internal use to ensure proper use of api.
    ## Prevents access to resources that shouldn't be accessed.

  ApiErr = object
    statusCode: int
    message: string

  # TODO: Split this up into a protocol instead of local storage, maybe come up with a way to decentralize it
  ServerCtx = ref object
    registeredTokens: Table[AccountAuthToken, Account]
    communities: seq[Community]


# TODO: Make use of this once closure iterators are fixes, if ever
# Copying permissions is an error. They must be consumed
#proc `=copy`*(a: var PermissionHandle, b: PermissionHandle) {.error.}


proc hash(x: AccountAuthToken): Hash {.borrow.}
proc `==`(a, b: AccountAuthToken): bool {.borrow.}

proc `==`(a, b: IdentityId): bool {.borrow.}

proc `$`(x: PublicName): string = x.string

proc `==`(a, b: CommunityId): bool {.borrow.}

proc `==`(a, b: ChannelId): bool {.borrow.}


proc getErrUnauthorized(): ApiErr {.inline.} =
  ApiErr(
    statusCode : 401,
    message : "Unauthorized",
  )

proc getErrNotFound(): ApiErr {.inline.} =
  ApiErr(
    statusCode : 404,
    message : "Not found",
  )

proc getErrBadData(messageStr: string): ApiErr {.inline.} =
  ApiErr(
    statusCode : 422,
    message : messageStr,
  )

template errUnauthorized(): untyped = err getErrUnauthorized()
template errNotFound(): untyped = err getErrNotFound()
template errBadData(messageStr: string): untyped = err getErrBadData(messageStr)



proc createAccount(server: ServerCtx): tuple[account: Account, token: AccountAuthToken] =
  let token = genOid().AccountAuthToken
  let account = Account(
    accountId : genOid().AccountId,
    identities : newSeq(),
    isDeleted : false,
  )
  server.registeredTokens[token] = account
  (account : account, token : token)

proc createChannel(permissionHandle: sink PermissionHandle, community: Community, name: PublicName): Channel =
  let channel = Channel(
    channelId : genOid().ChannelId,
    name : name,
    posts : @[]
  )
  # FIXME: race condition
  community.channels.add(channel)
  channel



proc getAuthToken(headers: HttpHeaders): Result[AccountAuthToken, ApiErr] =
  const authHeaderKey = "Authorization"
  if not headers.hasKey(authHeaderKey):
    errUnauthorized()
  else:
    ok headers[authHeaderKey].`$`.cstring.parseOid().AccountAuthToken

proc validateAccount(server: ServerCtx, headers: HttpHeaders): Result[Account, ApiErr] =
  headers.getAuthToken().ifOk(token, error):
    if token notin server.registeredTokens:
      return errUnauthorized()
    return ok server.registeredTokens[token]
  do:
    return err error

proc validateIdentity(account: Account, identityId: IdentityId): Result[Identity, ApiErr] =
  for identity in account.identities:
    if identity.identityId == identityId:
      return ok(identity)
  errUnauthorized()

proc validateIdentity(server: ServerCtx, headers: HttpHeaders): Result[Identity, ApiErr] =
  const identityHeaderKey = "Identity"
  if not headers.hasKey(identityHeaderKey):
    errUnauthorized()
  else:
    server.validateAccount(headers).ifOk(account, error):
      let identityId = headers[identityHeaderKey].`$`.cstring.parseOid().IdentityId
      account.validateIdentity(identityId)
    do:
      err error

proc validateCommunity(identity: Identity, communityId: CommunityId): Result[Community, ApiErr] =
  for community in identity.memberOf:
    if community.communityId == communityId:
      return ok community
  errUnauthorized()

proc validateModerationPermissions(community: Community, identity: Identity): Result[PermissionHandle, ApiErr] =
  # TODO: Support for roles and actions once they are added
  if community.owner.identityId == identity.identityId:
    return ok PermissionHandle()
  errUnauthorized()

# TODO: Restrict view based on badges once they exist
proc validateChannel(community: Community, channelId: ChannelId): Result[Channel, ApiErr] =
  for channel in community.channels:
    if channel.channelId == channelId:
      return ok channel
  errNotFound()


proc validateName(name: string): Result[PublicName, ApiErr] =
  const maxLen = 32

  # FIXME: The unicode module does not understand zero width space and friends as whitespace.
  let name = unicode.strip(name)
  let len = name.runeLen()
  if len == 0:
    errBadData("Name must be at least 1 character long.")
  elif len > maxLen:
    errBadData("Name must be at most " & $maxLen & " characters long.")
  else:
    ok(name.PublicName)


proc toJson(x: Post): JsonNode =
  %* {
    "id": $x.postId.Oid,
    "author": $x.author.identityId.Oid,
    "contents": x.contents,
  }


# TODO: Validate json payload structurally

randomize()
serve "127.0.0.1", 5000:
  setup:
    let serverCtx = ServerCtx()

  wsConnect:
    echo "Connected"
    echo req.headers

  ws "/listen":
    echo "Listen"
    echo wsData

  post "/register":
    # TODO: Actual registration
    let (account, accountToken) = serverCtx.createAccount()
    return %* { "token": $accountToken.Oid, "id": $account.accountId.Oid}

  post "/create_community":
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      # FIXME
      let payload = req.body.parseJson()
      validateName(payload["name"].getStr()).ifOk(name, error):
        when defined(debug):
          echo "Creating community"
          echo "Name: ", name
          echo "Owner: ", identity.name, " | ", identity.identityId.Oid
        let community = Community(
          communityId : genOid().CommunityId,
          name : name,
          owner : identity,
          members : @[identity],
          channels : @[],
        )
        # FIXME: race conditions
        identity.memberOf.add(community)
        serverCtx.communities.add(community)
        return %* { "name": name.string, "id": $community.communityId.Oid, "owner": $identity.identityId.Oid }
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message

  post "/create_identity":
    serverCtx.validateAccount(headers).ifOk(account, error):
      # FIXME
      let payload = req.body.parseJson()
      validateName(payload["name"].getStr()).ifOk(name, error):
        let identity = Identity(
          identityId : genOid().IdentityId,
          name : name,
          sourceAccount : account,
          memberOf : @[],
        )
        # FIXME: race condition
        account.identities.add(identity)
        return %* { "name": $identity.name, "id": $identity.identityId.Oid }
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message

  post "/delete_identity":
    serverCtx.validateAccount(headers).ifOk(account, error):
      # FIXME
      let
        payload = req.body.parseJson()
        identityId = payload["id"].getStr().cstring.parseOid().IdentityId
      # FIXME: race condition
      for i in countdown(account.identities.len() - 1, 0):
        let identity = account.identities[i]
        if identity.identityId == identityId:
          for community in identity.memberOf:
            if community.owner.identityId == identity.identityId:
              statusCode = 422
              # TODO: Provide a way to tell which communities an identity owns
              return "This identity owns at least one community and cannot be deleted"
          # TODO: must iterate twice for now to ensure clean deletion
          # delete the identity from every community it's in
          for community in identity.memberOf:
            for j in countdown(community.members.len() - 1, 0):
              if community.members[j].identityId == identity.identityId:
                community.members.del(j)
                break # done with this community
          account.identities.del(i)
          return ""
      statusCode = 404
      return "Identity not found"
    do:
      statusCode = error.statusCode
      return error.message

  get "/identities":
    serverCtx.validateAccount(headers).ifOk(account, error):
      let identityJList = newJArray()
      for identity in account.identities:
        let communityJList = newJArray()
        for community in identity.memberOf:
          communityJList.add(%* { "id": $community.communityId.Oid, "name": $community.name })
        identityJList.add(%* { "id": $identity.identityId.Oid, "name": $identity.name, "communities": communityJList })
      return %* { "identities": identityJList }
    do:
      statusCode = error.statusCode
      return error.message


  # community
  post "/community/{communityId:string}/create_channel":
    # FIXME
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      let payload = req.body.parseJson()
      payload["name"].getStr().validateName().ifOk(name, error):
        identity.validateCommunity(communityId.cstring.parseOid().CommunityId).ifOk(community, error):
          community.validateModerationPermissions(identity).ifOk(permissionHandle, error):
            let channel = permissionHandle.createChannel(community, name)
            return %* { "name": name.string, "id": $channel.channelId.Oid }
          do:
            statusCode = error.statusCode
            return error.message
        do:
          statusCode = error.statusCode
          return error.message
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message

  post "/community/{communityId:string}/channels/{channelId:string}/posts":
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      # FIXME
      let
        payload = req.body.parseJson()
        # TODO: Non string message contents (embeds/images), restrict message length, sanitize
        messageContents = payload["contents"].getStr()
      identity.validateCommunity(communityId.cstring.parseOid().CommunityId).ifOk(community, error):
        community.validateChannel(channelId.cstring.parseOid().ChannelId).ifOk(channel, error):
          # FIXME: race condition
          let post = Post(
            postId : genOid().PostId,
            author : identity,
            contents : messageContents,
          )
          channel.posts.add(post)
          return post.toJson()
        do:
          statusCode = error.statusCode
          return error.message
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message


  delete "/community/{communityId:string}":
    discard

  delete "/community/{communityId:string}/channels/{channelId:string}":
    discard

  delete "/community/{communityId:string}/channels/{channelId:string}/posts/{postdId:string}":
    discard

  get "/community/{communityId:string}/members":
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      identity.validateCommunity(communityId.cstring.parseOid().CommunityId).ifOk(community, error):
        let membersJArray = newJArray()
        for member in community.members:
          membersJArray.add(%* {
            "id": $member.identityId.Oid,
            "name": $member.name
          })
        return %* { "members": membersJArray }
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message

  get "/community/{communityId:string}/members/{identityId:string}":
    discard

  get "/community/{communityId:string}/channels":
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      identity.validateCommunity(communityId.cstring.parseOid().CommunityId).ifOk(community, error):
        let channelsJArray = newJArray()
        # TODO: Only list channels the identity is allowed to see
        for channel in community.channels:
          channelsJArray.add(%* {
            "id": $channel.channelId.Oid,
            "name": $channel.name,
          })
        return %* { "channels": channelsJArray }
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message

  get "/community/{communityId:string}/channels/{channelId:string}/posts/latest":
    ## Get at most 20 most recent posts
    serverCtx.validateIdentity(headers).ifOk(identity, error):
      identity.validateCommunity(communityId.cstring.parseOid().CommunityId).ifOk(community, error):
        community.validateChannel(channelId.cstring.parseOid().ChannelId).ifOk(channel, error):
          let postsJList = newJArray()
          for i in 0 ..< min(20, channel.posts.len()):
            postsJList.add(channel.posts[channel.posts.len() - i - 1].toJson())
          return %* { "posts": postsJList }
        do:
          statusCode = error.statusCode
          return error.message
      do:
        statusCode = error.statusCode
        return error.message
    do:
      statusCode = error.statusCode
      return error.message


  get "/community/{communityId:string}/channels/{channelId:string}/posts/before/{postId:string}":
    ## get at most 20 posts before postId
    discard

  get "/community/{communityId:string}/channels/{channelId:string}/posts/after/{postId:string}":
    ## get at most 20 posts after postId
    discard
