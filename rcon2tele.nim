import os, asyncdispatch, strutils, websocket, telebot, cligen, parsecfg, json

var
  tg_operators: seq[string]
  tg_chat_id: int
  tg_updates: seq[Update]

  ws: AsyncWebsocket
  bot: TeleBot

proc readRcon() {.async.} =
  while true:
    let read = await ws.sock.readData(true)
    echo "read: " & $read
    if read.opcode == OpCode.Text:
      let
        data = parseJson(read.data)
        typ = getStr(data["Type"])

      if typ == "Chat":
        let msg = parseJson(getStr(data["Message"]))
        discard await bot.sendMessageAsync(tg_chat_id, "<" & getStr(msg["Username"]) & "> " & getStr(msg["Message"]))
      else:
        let msg = getStr(data["Message"])
        if startsWith(msg, "[CHAT]"):
          continue
        discard await bot.sendMessageAsync(tg_chat_id, "```\n" & msg & "\n```", parseMode = "Markdown")

proc readTelegram() {.async.} =
  while true:
    tg_updates = bot.getUpdates(timeout = 300)
    for update in tg_updates:
      if update.message.kind == kText and $update.message.fromUser.id in tg_operators:
        let cmd = %*{
          "Identifier": 10001,
          "Message": update.message.text,
          "Name": "WebRcon"
        }
        echo $cmd
        await ws.sock.sendText($cmd, true)


proc app(config = "config.ini") =
  ## Websocket RCON to Telegram bridge
  if not fileExists(config):
    quit("Config file " & config & " does not exists")

  let
    dict = loadConfig(config)

    rcon_host = strip(dict.getSectionValue("RCON","host"))
    rcon_port = Port parseInt(dict.getSectionValue("RCON","port"))
    rcon_password = strip(dict.getSectionValue("RCON","password"))

    tg_token = strip(dict.getSectionValue("TELEGRAM","token"))

  tg_operators = split(strip(dict.getSectionValue("TELEGRAM","operators")), " ")
  tg_chat_id = parseInt(dict.getSectionValue("TELEGRAM", "chat_id"))

  ws = waitFor newAsyncWebsocket(rcon_host, rcon_port, "/" & rcon_password, ssl = false)
  bot = newTeleBot(tg_token)

  echo "connected"

  asyncCheck readRcon()
  asyncCheck readTelegram()
  runForever()




when isMainModule:
  dispatch(app)
