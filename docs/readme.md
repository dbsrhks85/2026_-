기획서, API 명세서, 회의록 폴더
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
