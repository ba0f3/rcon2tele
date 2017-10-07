import os, asyncdispatch, asyncnet, strutils, websocket, telebot, cligen, parsecfg, json, daemonize

var
  isSending = false
  rcon_uri: string
  tg_operators: seq[string]
  tg_chat_id: int
  tg_updates: seq[Update]
  tg_queues: seq[string] = @[]

  ws: AsyncWebsocket
  bot: TeleBot

proc connectRcon() =
  while true:
    try:
      ws = waitFor newAsyncWebsocket(rcon_uri)
      break
    except:
      waitFor sleepAsync(5000)

  echo "Connected to WS server"

proc readRcon() {.async.} =
  var
    msg: string

  while true:
    var read: tuple[opcode: Opcode, data: string]
    try:
      read = await ws.sock.readData(true)
    except:
      if getCurrentException() of IOError:
        echo "WS connection closed, reconnecting.."
        connectRcon()
        ws = waitFor newAsyncWebsocket(rcon_uri)
        continue
      else:
        echo "Got exception ", repr(getCurrentException()), " with message: ", getCurrentExceptionMsg()

    if read.opcode == OpCode.Text:
      let
        data = parseJson(read.data)
        kind = getStr(data["Type"])

      if kind == "Chat":
        let jobj = parseJson(getStr(data["Message"]))
        msg = "<" & getStr(jobj["Username"]) & "> " & getStr(jobj["Message"])
      else:
        msg = getStr(data["Message"])
        if startsWith(msg, "[CHAT]"):
          continue
        if startsWith(msg, "Saved "):
          continue
        if startsWith(msg, "Saving "):
          continue
      tg_queues.add(msg)

proc readTelegram() {.async.} =
  while true:
    try:
      tg_updates = await bot.getUpdates(timeout = 300)
    except:
      continue

    for update in tg_updates:

      if update.message.isSome:
        var response = update.message.get
        if response.text.isNone:
          continue
        let
          user = response.fromUser.get
          text = response.text.get

        if $user.id in tg_operators:
          let cmd = %*{
            "Identifier": 10001,
            "Message": text,
            "Name": "rcon2tele"
          }
          if ws.sock.isClosed():
            tg_queues.add("Websocket connection closed!")
          else:
            await ws.sock.sendText($cmd, true)
        else:
          try:
            tg_queues.add("Permission denied")
          except:
            continue

proc sendTelegram() {.async.} =
  var
    queue: string
    message: string
    length: int

  while true:
    message = ""
    if not isSending:
      isSending = true
      while len(tg_queues) > 0:
        queue = tg_queues[0]
        length = len(message)

        if message == "" and len(queue) > 1000:
          message = substr(queue, 0, 1000)
          tg_queues[0] = substr(queue, 1000)
          break

        length += len(queue)
        if length >= 1000:
          break

        message &= "\n" & queue
        delete(tg_queues, 0)

      if message != "":
        try:
          var message = newMessage(tg_chat_id, message)
          message.disableNotification = true
          message.parseMode = "markdown"
          discard await bot.send(message)
        except:
          discard
      isSending = false

    await sleepAsync(1000)

proc ping() {.async.} =
  while true:
    await sleepAsync(6000)
    if not ws.sock.isClosed():
      await ws.sock.sendPing(true)

proc app(config = "config.ini") =
  ## Websocket RCON to Telegram bridge
  if not fileExists(config):
    quit("Config file " & config & " does not exists")

  let
    dict = loadConfig(config)

    rcon_host = strip(dict.getSectionValue("RCON","host"))
    rcon_port = parseInt(dict.getSectionValue("RCON","port"))
    rcon_password = strip(dict.getSectionValue("RCON","password"))

    tg_token = strip(dict.getSectionValue("TELEGRAM","token"))

  tg_operators = split(strip(dict.getSectionValue("TELEGRAM","operators")), " ")
  tg_chat_id = parseInt(dict.getSectionValue("TELEGRAM", "chat_id"))

  rcon_uri = "ws://" & rcon_host & ":" & $rcon_port & "/" & rcon_password

  connectRcon()
  bot = newTeleBot(tg_token)

  echo "connected"

  asyncCheck readRcon()
  asyncCheck readTelegram()
  asyncCheck sendTelegram()
  asyncCheck ping()
  runForever()

when isMainModule:
  let
    logfile = "/var/log/rcon2tele.log"
    pidfile = "/var/log/rcon2tele.pid"
  daemonize(pidfile, logfile, logfile, logfile, nil):
    dispatch(app)
