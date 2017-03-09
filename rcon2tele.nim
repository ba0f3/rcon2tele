import os, asyncdispatch, asyncnet, strutils, websocket, telebot, cligen, parsecfg, json, daemonize

var
  rcon_uri: string
  tg_operators: seq[string]
  tg_chat_id: int
  tg_updates: seq[Update]

  ws: AsyncWebsocket
  bot: TeleBot

proc readRcon() {.async.} =
  var
    msg: string

  while true:
    if ws.sock.isClosed():
      ws = await newAsyncWebsocket(rcon_uri)

    var read: tuple[opcode: Opcode, data: string]
    try:
      read = await ws.sock.readData(true)
    except:
      if getCurrentException() of IOError:
        ws = waitFor newAsyncWebsocket(rcon_uri)
        break
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
      msg = "```\n" & msg & "\n```"
      discard await bot.sendMessageAsync(tg_chat_id, msg, parseMode = "Markdown", retry = 5)

proc readTelegram() {.async.} =
  while true:
    try:
      tg_updates = await bot.getUpdatesAsync(timeout = 300)
    except:
      continue

    for update in tg_updates:
      if update.message.kind == kText:
        if $update.message.fromUser.id in tg_operators:
          let cmd = %*{
            "Identifier": 10001,
            "Message": update.message.text,
            "Name": "rcon2tele"
          }
          if ws.sock.isClosed():
            discard await bot.sendMessageAsync(tg_chat_id, "Websocket connection closed!")
          else:
            await ws.sock.sendText($cmd, true)
        else:
          try:
            discard await bot.sendMessageAsync(tg_chat_id, "Permission denied")
          except:
            continue

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

  ws = waitFor newAsyncWebsocket(rcon_uri)
  bot = newTeleBot(tg_token)

  echo "connected"

  asyncCheck readRcon()
  asyncCheck readTelegram()
  asyncCheck ping()
  runForever()

when isMainModule:
  let
    logfile = "/var/log/rcon2tele.log"
    pidfile = "/var/run/rcon2tele.pid"
  daemonize(pidfile, logfile, logfile, logfile, nil):
    dispatch(app)
