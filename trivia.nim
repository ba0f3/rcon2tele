import os

type
  Trivia* = ref object
    isRunning*: bool
    questionDir: string
    questionFiles: seq[string]
    question*: string
    anwser*: string


proc newTrivia*(dir: string): Trivia =
  result = new(Trivia)

  result.questionDir = dir
  result.isRunning = false
  result.question = ""
  result.answer = ""

  result.loadQuestionFiles()

proc loadQuestionFiles*(t: Trivia) =
  t.questionFiles = @[]
  for kind, path in walkDir(t.questionDir):
    t.questionFiles.add(path)


proc getNewQuestion*(t: Trivia) =
  let file = random(t.questionFiles)

proc start*(t: Trivia) =
  if t.isRunning:
    echo "The game is already running"
    return

  t.isRunning = true
