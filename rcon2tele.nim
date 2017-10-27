import os, asyncdispatch, asyncnet, strutils, websocket, cligen, parsecfg, json, daemonize, trivia, options
import telebot

const
  TRIVIA = 10_000
  SERVER_INFO = 100

var
  isSending = false
  rcon_uri: string
  tg_operators: seq[string]
  tg_chat_id: int
  tg_queues: seq[string] = @[]

  ws: AsyncWebsocket
  bot: TeleBot
  game: Trivia

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
        continue
      else:
        echo "Got exception ", repr(getCurrentException()), " with message: ", getCurrentExceptionMsg()

    if read.opcode == OpCode.Text:
      let
        data = parseJson(read.data)
        kind = getStr(data["Type"])

      if kind == "Chat":
        let
          jobj = parseJson(getStr(data["Message"]))
          chatMsg = getStr(jobj["Message"])
        asyncCheck game.matchAnswer(chatMsg, getNum(jobj["UserId"]).int)

        msg = "<" & getStr(jobj["Username"]) & "> " & chatMsg
      else:
        msg = getStr(data["Message"])
        if startsWith(msg, "[CHAT]"):
          continue
        if startsWith(msg, "Saved "):
          continue
        if startsWith(msg, "Saving "):
          continue
      tg_queues.add(msg)

proc updateHandler(bot: TeleBot, ws: AsyncWebSocket, operators: seq[string], queues: ptr seq[string]): UpdateCallback =
  proc cb(e: Update) {.async.} =
    if e.message.isSome:
      var response = e.message.get
      if response.text.isSome:
        let
          user = response.fromUser.get
          text = response.text.get

        if text[0] == '!' and $user.id in operators:
          echo "Command: " & text
          let cmd = %*{
            "Identifier": 10001,
            "Message": text[1..<text.len],
            "Name": "rcon2tele"
          }
          if ws.sock.isClosed():
            queues[].add("Websocket connection closed!")
          else:
            await ws.sock.sendText($cmd, true)
        else:
          queues[].add("Permission denied")

  result = cb

proc readTelegram() {.async.} =
  let handler = updateHandler(bot, ws, tg_operators, addr tg_queues)
  bot.onUpdate(handler)
  discard bot.poll(300)

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
          discard await bot.send(message)
        except:
          discard
      isSending = false

    await sleepAsync(1_000)

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

    trivia_data_dir = strip(dict.getSectionValue("TRIVIA","data_dir"))
    trivia_rewards_file = strip(dict.getSectionValue("TRIVIA","rewards_file"))


  tg_operators = split(strip(dict.getSectionValue("TELEGRAM","operators")), " ")
  tg_chat_id = parseInt(dict.getSectionValue("TELEGRAM", "chat_id"))

  rcon_uri = "ws://" & rcon_host & ":" & $rcon_port & "/" & rcon_password

  connectRcon()
  bot = newTeleBot(tg_token)
  game = newTrivia(trivia_data_dir, trivia_rewards_file, ws)
  game.register(bot)

  asyncCheck readRcon()
  asyncCheck sendTelegram()
  asyncCheck readTelegram()
  asyncCheck ping()
  runForever()

proc main(config="config.ini", daemonized=false) =
  let
    logfile = "/var/log/rcon2tele.log"
    pidfile = "/var/log/rcon2tele.pid"
  if daemonized:
    daemonize(pidfile, logfile, logfile, logfile, nil):
      app(config)
  else:
    app(config)

when isMainModule:
  dispatch(main)
