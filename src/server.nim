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
    messages: seq[Post]

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



template errUnauthorized(): untyped =
  err ApiErr(
    statusCode : 401,
    message : "Unauthorized"
  )

template errBadData(messageStr: string): untyped =
  err ApiErr(
    statusCode : 422,
    message : messageStr,
  )



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
    messages : @[]
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
    serverCtx.validateAccount(headers).ifOk(account, error):
      # FIXME
      let
        payload = req.body.parseJson()
        identityId = payload["identity"].getStr().cstring.parseOid().IdentityId()
      account.validateIdentity(identityId).ifOk(identity, error):
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
    serverCtx.validateAccount(headers).ifOk(account, error):
      # FIXME
      let
        payload = req.body.parseJson()
        identityId = payload["identity"].getStr().cstring.parseOid().IdentityId()
      payload["name"].getStr().validateName().ifOk(name, error):
        account.validateIdentity(identityId).ifOk(identity, error):
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
    do:
      statusCode = error.statusCode
      return error.message

  post "/community/{communityId:string}/channel/{channelId:string}/send_message":
    discard

  delete "/community/{communityId:string}":
    discard

  delete "/community/{communityId:string}/channels/{channelId:string}":
    discard

  delete "/community/{communityId:string}/channels/{channelId:string}/posts/{postdId:string}":
    discard

  get "/community/{communityId:string}/members/":
    discard

  get "/community/{communityId:string}/members/{identityId:string}":
    discard

  get "/community/{communityId:string}/channels/":
    discard

  get "/community/{communityId:string}/channels/{channelId:string}/posts/before/{postId:string}":
    discard

  get "/community/{communityId:string}/channels/{channelId:string}/posts/after/{postId:string}":
    discard
