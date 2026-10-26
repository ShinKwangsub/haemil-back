import Base

# 마우스 옆 버튼을 Safari·Chrome·Finder 의 뒤로·앞으로 단축키로 바꾼다.
# side.c 는 맥 이벤트 탭·메뉴 막대 아이콘·키 보내기 경계만 맡고, 무엇을 할지는 이 파일이 정한다.

type Nav is Data:
  Back{}
  Forward{}

# 경계에서 오는 것: 옆 버튼 눌림(3번 이상), 또는 메뉴 막대에서 고른 끄기.
type Input is Data:
  Press{button: U32}
  Quit{}

# 다음 옆 버튼이나 메뉴 선택을 기다린다. 3·4번은 앱에 가지 않게 삼킨다. 처음 부를 때 아이콘과 탭을 연다.
def SideButton.wait() -> IO(Result<&1, &1, U32 & String, Input>):
  import "./side.c"

# 키 하나를 수정키(CGEventFlags)와 함께 눌렀다 뗀다.
def Keys.tap(code: U32, flags: U32) -> IO(Unit):
  import "./side.c"

def Nav.pick(back: Bool, fwd: Bool) -> Maybe<&2, Nav>:
  match back fwd:
    case True{} _:
      Some{Back{}}
    case False{} True{}:
      Some{Forward{}}
    case False{} False{}:
      None{}

# 3번(아래쪽 옆 버튼)은 뒤로, 4번(위쪽)은 앞으로.
def Nav.of(+button: U32) -> Maybe<&2, Nav>:
  Nav.pick(U32.is_eq(button, 3), U32.is_eq(button, 4))

# ⌘[ 와 ⌘] (자판 코드 33·30, 명령 키 0x100000). 한글 입력 중에도 명령 키 조합은 그대로 간다.
def Nav.go(n: Nav) -> IO(Unit):
  match n:
    case Back{}:
      Keys.tap(33, 1048576)
    case Forward{}:
      Keys.tap(30, 1048576)

def Back.run(m: Maybe<&2, Nav>, button: U32) -> IO(Unit):
  match m:
    case Some{n}:
      Nav.go(n)
    case None{}:
      IO.print_err("버튼 " ++ U32.show(button) ++ " 은 정한 동작이 없어 그대로 둡니다")

def Back.press(+button: U32) -> IO(Unit):
  Back.run(Nav.of(button), button)

def Back.loop(fuel: Nat, i: Input) -> IO(Unit):
  match fuel i:
    case 0n _:
      IO.pure(Unit, Unit{})
    case 1n+f Quit{}:
      IO.print_err("메뉴에서 종료했습니다")
    case 1n+f Press{b}:
      do IO<Unit>:
        u : Unit <- Back.press(b)
        nx : Input <- IO.try(Input, SideButton.wait())
        Back.loop(f, nx)

def main() -> IO(Unit):
  do IO<Unit>:
    i : Input <- IO.try(Input, SideButton.wait())
    Back.loop(4294967295n, i)
