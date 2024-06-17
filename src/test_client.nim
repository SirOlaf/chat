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
  block:
    echo "Creating identity: 'chatmaster'"
    let resp = await client.sendCreateIdentity("chatmaster")
    echo resp.code()
    echo await resp.body

  let identityToDelete = block:
    echo "Creating identity: 'sirolaf'"
    let resp = await client.sendCreateIdentity("sirolaf")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId


  block:
    echo "Listing identities"
    let resp = await client.sendListIdentities()
    echo resp.code()
    echo await resp.body()

  block:
    echo "Deleting identity 'sirolaf'"
    let resp = await client.sendDeleteIdentity(identityToDelete)
    echo resp.code()
    echo await resp.body()

  block:
    echo "Listing identities"
    let resp = await client.sendListIdentities()
    echo resp.code()
    echo await resp.body()

  block:
    echo "Trying to delete the same identity again"
    let resp = await client.sendDeleteIdentity(identityToDelete)
    echo resp.code()
    echo await resp.body()

  block:
    echo "Listing identities"
    let resp = await client.sendListIdentities()
    echo resp.code()
    echo await resp.body()

  let otherIdentity = block:
    echo "Creating identity again: 'sirolaf'"
    let resp = await client.sendCreateIdentity("sirolaf")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId

  block:
    echo "Trying to send an empty identity name"
    let resp = await client.sendCreateIdentity("")
    echo resp.code()
    echo await resp.body()

  block:
    echo "Trying to send a huge identity name"
    let resp = await client.sendCreateIdentity("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    echo resp.code()
    echo await resp.body()

  block:
    echo "Trying to send spaces as name"
    let resp = await client.sendCreateIdentity("​")
    echo resp.code()
    echo await resp.body()

  let testIdentity = block:
    echo "Sending a unicode name"
    let resp = await client.sendCreateIdentity("古手梨花")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().IdentityId


  block:
    echo "Listing identities"
    let resp = await client.sendListIdentities()
    echo resp.code()
    echo await resp.body()

  let communityId = block:
    echo "Creating a community"
    let resp = await client.sendCreateCommunity(testIdentity, "test community")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().CommunityId

  block:
    echo "Listing identities"
    let resp = await client.sendListIdentities()
    echo resp.code()
    echo await resp.body()

  let channelId = block:
    echo "Creating a channel"
    let resp = await client.sendCreateChannel(communityId, testIdentity, "test channel")
    echo resp.code()
    let body = await resp.body()
    echo body
    let payload = body.parseJson()
    payload["id"].getStr().ChannelId

  block:
    echo "Trying to create a channel as non owner"
    let resp = await client.sendCreateChannel(communityId, otherIdentity, "test channel")
    echo resp.code()
    echo await resp.body()

  block:
    echo "Sending a message"
    let resp = await client.sendChannelMessage(communityId, channelId, testIdentity, "Test message")
    echo resp.code()
    echo await resp.body()

  block:
    echo "Requesting latest messages from test channel"
    let resp = await client.getLatestChannelMessages(communityId, channelId, testIdentity)
    echo resp.code()
    echo await resp.body()

  block:
    echo "Requesting channel list"
    let resp = await client.getChannels(communityId, testIdentity)
    echo resp.code()
    echo await resp.body()

waitFor main()