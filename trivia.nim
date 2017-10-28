import os, random, asyncdispatch, asyncnet, strutils, websocket, json
import telebot

randomize()

type
  Trivia* = ref object
    isRunning: bool
    isAnswered: bool
    questionDir: string
    rewardFile: string
    questions: seq[string]
    questionCount: int
    question: string
    answers: seq[string]
    ws: AsyncWebsocket
    rewards: seq[tuple[item: string, max: int]]
    rewardCount: int

proc loadQuestions*(t: Trivia) =
  var file: system.File
  t.questions = @[]
  for kind, path in walkDir(t.questionDir):
    file = open(path)
    for line in file.lines:
      if not isNilOrEmpty(line):
          t.questions.add(line)
    file.close()
  t.questionCount = t.questions.len
  echo "Trivia: loaded " & $t.questionCount & " questions"

proc loadRewards(t: Trivia) =
  t.rewards = @[]
  let f = open(t.rewardFile)
  for line in f.lines:
    if not isNilOrEmpty(line):
      let
        reward = line.split('`')
        max_items = parseInt(reward[1])
      if max_items < 1:
        continue
      t.rewards.add((reward[0], max_items))
      #echo "Loaded new reward: ", reward[0], " max items: ", reward[1]
  t.rewardCount = t.rewards.len
  echo "Trivia: loaded " & $t.rewardCount & " rewards"
  f.close()

proc newTrivia*(dir: string, rewards: string, ws: AsyncWebsocket): Trivia =
  result = new(Trivia)

  result.rewardFile = rewards
  result.questionDir = dir
  result.isRunning = false
  result.isAnswered = false
  result.questions = @[]
  result.question = ""
  result.answers = @[]

  result.ws = ws

proc isRunning*(t: Trivia): bool =
  return t.isRunning

proc newQuestion*(t: Trivia) =
  let
    rand = random(t.questionCount)
    question = t.questions[rand]

  let tmp = question.split('`')
  t.question = tmp[0]
  t.answers = toLower(strip(tmp[1])).split('|')
  t.isAnswered = false

proc start*(t: Trivia) {.async.} =
  if t.isRunning:
    echo "The game is already running"
    return
  echo "Trivia game is starting"

  t.loadRewards()
  t.loadQuestions()

  t.isRunning = true

  let cmd = %*{
    "Identifier": 10000,
    "Message": "say Trivia game will starts in 10s, you have 10s to anwser the questions.. have fun!",
    "Name": "trivia"
  }
  await t.ws.sock.sendText($cmd, true)
  await sleepAsync(10_000)
  while t.isRunning:
    t.newQuestion()

    if not t.ws.sock.isClosed():
      let cmd = %*{
        "Identifier": 10000,
        "Message": "say Q: " & t.question,
        "Name": "trivia"
      }
      await t.ws.sock.sendText($cmd, true)
    await sleepAsync(10_000)
    if not t.isAnswered:
      let timeUp = %*{
        "Identifier": 10000,
        "Message": "say Time's up!",
        "Name": "trivia"
      }
      await t.ws.sock.sendText($timeUp, true)
    t.isAnswered = true
    await sleepAsync(10_000)

proc stop*(t: Trivia) =
  t.isRunning = false
  t.isAnswered = false
  t.questions = @[]
  t.questionCount = 0
  t.rewards = @[]
  t.rewardCount = 0
  t.question = ""
  t.answers = @[]
  echo "Trivia game is stopped"


proc matchAnswer*(t: Trivia, answer: string, userId: int) {.async.} =
  if not t.isRunning:
    return
  if t.isAnswered:
    return

  if toLower(strip(answer)) in t.answers:
    t.isAnswered = true

    var
      reward_index = random(t.rewardCount)
      reward_item = t.rewards[reward_index][0]
      reward_num = t.rewards[reward_index][1]
    if reward_num > 1:
      reward_num = random(reward_num) + 1

    let cmd = %*{
      "Identifier": 10000,
      "Message": "inventory.giveto \"" & $userId & "\" \"" & reward_item & "\" \"" & $reward_num & "\"",
      "Name": "trivia"
    }
    await t.ws.sock.sendText($cmd, true)

proc onTriviaCommand*(t: Trivia): CommandCallback =
  proc cb(e: Command) {.async.} =
    if e.params.startsWith("start"):
      asyncCheck t.start()
    elif e.params.startsWith("stop"):
      t.stop
  result = cb
