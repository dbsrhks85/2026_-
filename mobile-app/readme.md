이 폴더는 앱 소스 코드(Flutter 또는 React Native) 폴더임
lib 폴더 속 파일이 개발 파일임
cd mobile-app : 터미널에서 파일 이동
flutter devices : 애뮬레이터 확인
flutter doctor : 환경 진단(내 개발 환경에 문제가 없는지 체크)
Android Studio에서 device manager 켜서 화면 띄우고~
flutter run : 가상 스마트폰 환경 켜놓기
-------------------------------
가상 스마트폰 환경이 켜져 있는 상태에서
r : 코드를 수정하고 저장을 누른 뒤, 터미널에서 r을 입력하면 화면에 반영됨
q : 실행 중인 앱을 끔
-------------------------------
flutter clean : 빌드 클린(코드는 맞는데 애러가 날 떄 찌꺼기 파일들을 싹 지워줌), 이후 flutter run을 하며 테스트

-------------------------------
# 1. Git 초기화 (해당 폴더를 Git이 관리하게 함)
git init

# 2. 내 계정 정보 설정 (최초 1회) -- 이건 대표로 내가 했음 ㄱㅊ을듯?
git config --global user.name "내 이름"
git config --global user.email "내 이메일"

# 3. GitHub 저장소 연결 -- 이것도 내가 했음 ㄱㅊ을듯?
git remote add origin https://github.com/계정명/저장소이름.git

-------------------------------
#*코드 수정하고 GitHub에 업로드하기 (Push).* 

① Add (변경사항 선택)
수정한 파일들을 '올릴 준비' 하는 단계

터미널: git add . (모든 변경사항 추가)
ex) git add test.py test2.py  <- 파일을 2개 추가하고 싶다면 이런식으로!

② Commit (버전 기록)
현재 상태를 스냅샷으로 저장하고 설명을 남기는 단계
!!**따옴표 안에 설명을 적어주기**!!
터미널: git commit -m "로그인 기능 구현 완료" 

③ Push (서버로 전송)
내 컴퓨터의 기록을 GitHub로 보내는 최종 단계
터미널: git push origin main 
여기에서 main은 브랜치의 이름임!
브랜치 이름을 우리가 다르게 모아놓고 관리하게 되면 main 부분만 바꿔서 해도 됨

-------------------------------
#팀원이 올렸던 코드 최신 버전 가져오기
git pull origin main <- 이것도 역시 브랜치 이름임 main 말고 다른 브랜치 이름이라면 다른 이름 적기!
-------------------------------
#🛡️ .gitignore에 담아야 할 것들
API Key 외에도 GitHub에 올라가면 안 되는 것들이 몇 가지 더 있어.

보안 관련 (가장 중요!):

API Key, 비밀번호, DB 접속 정보가 담긴 파일 (예: .env, config.py, secrets.json)

개발 환경 관련:

파이썬 가상환경 폴더 (예: venv/, env/)

라이브러리 설치 폴더 (예: node_modules/)

설정 및 임시 파일:

VS Code 설정 폴더 (예: .vscode/)

파이썬 캐시 파일 (예: __pycache__/)

OS 임시 파일 (예: Thumbs.db, .DS_Store)
-------------------------------





