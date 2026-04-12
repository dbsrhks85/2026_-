# STT 엔진 - OpenAI Whisper API를 사용한 음성→텍스트 변환
import os
from openai import AsyncOpenAI
from dotenv import load_dotenv
from messages import SttMessages

load_dotenv()
# [Fix #7] AsyncOpenAI 클라이언트로 전환 (async 함수 내 동기 호출 블로킹 방지)
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))


async def transcribe_audio(file_path: str) -> dict:
    """
    음성 파일을 받아 OpenAI Whisper API로 텍스트 변환

    Args:
        file_path: 음성 파일 경로 (m4a, wav, mp3 등)
    
    Returns:
        {"text": "변환된 텍스트", "success": True/False, "error": "에러 메시지"}
    """
    try:
        # 파일 존재 여부 확인
        if not os.path.exists(file_path):
            return {"text": "", "success": False, "error": SttMessages.FILE_NOT_FOUND}

        # Whisper API 호출 (한국어 최적화)
        # [Fix #7] await 추가 (AsyncOpenAI 사용)
        with open(file_path, "rb") as audio_file:
            transcript = await client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                language="ko",  # 한국어 인식 최적화
                response_format="text"
            )

        # 빈 결과 체크
        if not transcript or transcript.strip() == "":
            return {"text": "", "success": False, "error": SttMessages.EMPTY_TRANSCRIPT}

        return {"text": transcript.strip(), "success": True, "error": None}

    except Exception as e:
        return {"text": "", "success": False, "error": SttMessages.PROCESSING_ERROR.format(error=str(e))}
