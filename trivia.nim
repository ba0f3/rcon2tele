import os, random, asyncdispatch, asyncnet, strutils, websocket, json

type
  Trivia* = ref object
    isRunning: bool
    isAnswered: bool
    questionDir: string
    questionFiles: seq[string]
    question: string
    answer: string
    ws: AsyncWebsocket
    reward_item: string
    reward_num: int

proc loadQuestionFiles*(t: Trivia) =
  t.questionFiles = @[]
  for kind, path in walkDir(t.questionDir):
    t.questionFiles.add(path)

proc newTrivia*(dir: string, reward_item: string, reward_num: int, ws: AsyncWebsocket): Trivia =
  result = new(Trivia)

  result.questionDir = dir
  result.isRunning = false
  result.isAnswered = false
  result.question = ""
  result.answer = ""

  result.reward_item = reward_item
  result.reward_num = reward_num

  result.ws = ws

  result.loadQuestionFiles()

proc isRunning*(t: Trivia): bool =
  return t.isRunning


proc getNewQuestion*(t: Trivia) =
  var
    file = open(random(t.questionFiles))
    question: string
    count = 0

  for _ in file.lines:
    inc(count)

  let rand = random(count)
  count = 0
  file.setFilePos(0)
  for line in file.lines:
    if count == rand:
      if isNilOrEmpty(line):
        t.getNewQuestion()

      question = line
      break
    inc(count)

  let tmp = question.split('`')
  t.question = tmp[0]
  t.answer = toLower(strip(tmp[1]))


proc start*(t: Trivia) {.async.} =
  if t.isRunning:
    echo "The game is already running"
    return
  t.isRunning = true

  let cmd = %*{
    "Identifier": 10000,
    "Message": "say <color=yellow>Trivia game will starts in 15s, you have 10s to anwser the questions.. Have fun!</color>",
    "Name": "trivia"
  }
  await t.ws.sock.sendText($cmd, true)
  await sleepAsync(15_000)
  while t.isRunning:
    t.getNewQuestion()
    t.isAnswered = false
    echo t.answer
    if not t.ws.sock.isClosed():
      let cmd = %*{
        "Identifier": 10000,
        "Message": "say QUESTION: " & t.question,
        "Name": "trivia"
      }
      await t.ws.sock.sendText($cmd, true)
    await sleepAsync(10_000)

proc stop*(t: Trivia) =
  t.isRunning = false

proc matchAnswer*(t: Trivia, answer: string, userId: int) {.async.} =
  if not t.isRunning:
    return
  if t.isAnswered:
    return

  if t.answer == toLower(strip(answer)):
    echo "correct"
    t.isAnswered = true
    let cmd = %*{
      "Identifier": 10000,
      "Message": "inventory.giveto \"" & $userId & "\" \"" & t.reward_item & "\" \"" & $t.reward_num & "\"",
      "Name": "trivia"
    }
    await t.ws.sock.sendText($cmd, true)
