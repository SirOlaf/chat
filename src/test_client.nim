import std/[
  asyncdispatch,
  asynchttpserver,
  httpclient,
  json,
]

import ws

import results


{.experimental: "inferGenericTypes".}


type IdentityId = distinct string


const baseAddr = "http://127.0.0.1:5000/"



proc sendCreateIdentity(client: AsyncHttpClient, name: string): Future[AsyncResponse] {.async.} =
  await client.post(baseAddr & "create_identity", body = $(%* {"name": name}))

proc sendDeleteIdentity(client: AsyncHttpClient, id: IdentityId): Future[AsyncResponse] {.async.} =
  await client.post(baseAddr & "delete_identity", body = $(%* {"id": id.string}))

proc sendListIdentities(client: AsyncHttpClient): Future[AsyncResponse] {.async.} =
  await client.get(baseAddr & "identities")


proc sendCreateCommunity(client: AsyncHttpClient, identity: IdentityId, name: string): Future[AsyncResponse] {.async.} =
  await client.post(baseAddr & "create_community", body = $(%* {"identity": identity.string, "name": name}))



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

  block:
    echo "Creating a community"
    let resp = await client.sendCreateCommunity(testIdentity, "test community")
    echo resp.code()
    echo await resp.body()

waitFor main()