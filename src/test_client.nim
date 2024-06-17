import std/[
  asyncdispatch,
  asynchttpserver,
  httpclient,
  json,
]

import ws

import results


{.experimental: "inferGenericTypes".}


type
  IdentityId = distinct string
  CommunityId = distinct string
  ChannelId = distinct string


const baseAddr = "http://127.0.0.1:5000/"



proc sendCreateIdentity(client: AsyncHttpClient, name: string): Future[AsyncResponse] {.async.} =
  await client.post(baseAddr & "create_identity", body = $(%* {"name": name}))

proc sendDeleteIdentity(client: AsyncHttpClient, id: IdentityId): Future[AsyncResponse] {.async.} =
  await client.post(baseAddr & "delete_identity", body = $(%* {"id": id.string}))

proc sendListIdentities(client: AsyncHttpClient): Future[AsyncResponse] {.async.} =
  await client.get(baseAddr & "identities")


proc sendCreateCommunity(client: AsyncHttpClient, identity: IdentityId, name: string): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.post(baseAddr & "create_community", body = $(%* {"name": name}))

proc sendCreateChannel(client: AsyncHttpClient, community: CommunityId, identity: IdentityId, name: string): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.post(baseAddr & "community/" & community.string & "/create_channel", body = $(%* { "name": name }))

proc getChannels(client: AsyncHttpClient, community: CommunityId, identity: IdentityId): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.get(baseAddr & "community/" & community.string & "/channels")

proc getMembers(client: AsyncHttpClient, community: CommunityId, identity: IdentityId): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.get(baseAddr & "community/" & community.string & "/members")

proc sendChannelMessage(client: AsyncHttpClient, community: CommunityId, channel: ChannelId, identity: IdentityId, contents: string): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.post(
    baseAddr & "community/" & community.string & "/channels/" & channel.string & "/posts",
    body = $(%* {"contents": contents})
  )

proc getLatestChannelMessages(client: AsyncHttpClient, community: CommunityId, channel: ChannelId, identity: IdentityId): Future[AsyncResponse] {.async.} =
  client.headers["Identity"] = identity.string
  await client.get(
    baseAddr & "community/" & community.string & "/channels/" & channel.string & "/posts/latest",
  )

proc lookupIdentityById(client: AsyncHttpClient, targetId: Identityid): Future[AsyncResponse] {.async.} =
  await client.get(baseAddr & "identity_info/" & targetId.string)



template doBasic(message: string, action: Future[AsyncResponse]): untyped =
  echo message
  let resp = await action
  echo resp.code()
  echo await resp.body


proc main() {.async.} =
  let client = newAsyncHttpClient()
  let loginToken = block:
    let resp = await client.post(baseAddr & "register")
    if resp.code().int != 200:
      echo "Failed to register"
      quit(1)
    let body = (await resp.body()).parseJson()
    echo "Got account id: ", body["id"].getStr()
    body["token"].getStr()
  echo "Registered token: " & loginToken

  client.headers["Authorization"] = loginToken

  doBasic "Creating identity: 'chatmaster'", client.sendCreateIdentity("chatmaster")

  let identityToDelete = block:
    echo "Creating identity: 'sirolaf'"
    let resp = await client.sendCreateIdentity("sirolaf")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId


  doBasic "Listing identities", client.sendListIdentities()

  doBasic "Deleting identity 'sirolaf'", client.sendDeleteIdentity(identityToDelete)
  doBasic "Listing identities", client.sendListIdentities()

  doBasic "Trying to delete the same identity again", client.sendDeleteIdentity(identityToDelete)
  doBasic "Listing identities", client.sendListIdentities()

  let otherIdentity = block:
    echo "Creating identity again: 'sirolaf'"
    let resp = await client.sendCreateIdentity("sirolaf")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId

  doBasic "Trying to send an empty identity name", client.sendCreateIdentity("")
  doBasic "Trying to send a huge identity name", client.sendCreateIdentity("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  doBasic "Trying to send spaces as name", client.sendCreateIdentity("​")

  let testIdentity = block:
    echo "Sending a unicode name"
    let resp = await client.sendCreateIdentity("古手梨花")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId
  doBasic "Listing identities", client.sendListIdentities()

  let communityId = block:
    echo "Creating a community"
    let resp = await client.sendCreateCommunity(testIdentity, "test community")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().CommunityId
  doBasic "Listing identities", client.sendListIdentities()

  let channelId = block:
    echo "Creating a channel"
    let resp = await client.sendCreateChannel(communityId, testIdentity, "test channel")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().ChannelId

  doBasic "Trying to create a channel as non owner", client.sendCreateChannel(communityId, otherIdentity, "test channel")

  doBasic "Sending a message", client.sendChannelMessage(communityId, channelId, testIdentity, "Test message")

  doBasic "Requesting latest messages from test channel", client.getLatestChannelMessages(communityId, channelId, testIdentity)
  doBasic "Requesting channel list", client.getChannels(communityId, testIdentity)
  doBasic "Requesting members list", client.getMembers(communityId, testIdentity)

  doBasic "Attempting to delete an identity that owns communities", client.sendDeleteIdentity(testIdentity)
  doBasic "Listing identities", client.sendListIdentities()

  doBasic "Looking up own identity by id", client.lookupIdentityById(testIdentity)
  doBasic "Looking up other identity by id", client.lookupIdentityById(otherIdentity)
  doBasic "Looking up an identity that doesn't exist", client.lookupIdentityById(IdentityId("badid"))

waitFor main()