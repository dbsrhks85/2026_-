# NLP 분류 엔진 - GPT-4o mini를 사용한 민원 자동 분류
import os
import json
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# 민원 분류 카테고리 정의
CATEGORIES = {
    "repair": "파손/수리 — 시설물 파손, 도로 파손, 가로등 고장 등",
    "suggestion": "건의사항 — 정책 건의, 환경 개선, 쓰레기 무단투기 등",
    "inquiry": "문의/질문 — 행정 절차 문의, 서비스 이용 방법 등",
    "unclassified": "미분류 — 내용이 모호하거나 판단이 어려운 경우"
}

# 부서 매칭 테이블
DEPARTMENT_MAP = {
    "repair": "시설관리과",
    "suggestion": "민원봉사과",
    "inquiry": "민원봉사과",
    "unclassified": "민원봉사과"
}

# GPT에게 전달할 시스템 프롬프트
SYSTEM_PROMPT = """당신은 춘천시 민원 분류 AI 시스템입니다.
시민의 민원 내용을 분석하여 아래 4가지 카테고리 중 하나로 정확히 분류하고, 
요약된 제목을 만들어주세요.

## 분류 카테고리
- repair: 시설물 파손, 도로 파손, 가로등 고장, 간판 파손, 상수도 누수 등 물리적 수리가 필요한 경우
- suggestion: 정책 건의, 환경 개선, 불법 주정차 단속 요청, 쓰레기 무단투기 신고 등
- inquiry: 행정 절차 문의, 서비스 이용 방법, 증명서 발급 관련 질문 등
- unclassified: 위 세 가지에 해당하지 않거나 내용이 모호한 경우

## 응답 형식 (반드시 JSON으로만 답변)
{
    "title": "20자 이내의 간결한 민원 제목",
    "category": "repair 또는 suggestion 또는 inquiry 또는 unclassified",
    "confidence": 0.0~1.0 사이의 분류 신뢰도
}

주의사항:
- 반드시 유효한 JSON만 출력하세요.
- title은 20자 이내로 핵심만 요약하세요.
- 확신이 없으면 category를 "unclassified"로, confidence를 낮게 설정하세요.
"""


async def classify_complaint(text: str) -> dict:
    """
    STT 텍스트를 받아 GPT-4o mini로 민원 분류

    Args:
        text: STT로 변환된 민원 텍스트
    
    Returns:
        {
            "title": "요약된 민원 제목",
            "category": "repair|suggestion|inquiry|unclassified",
            "department": "담당 부서명",
            "confidence": 0.95,
            "success": True/False,
            "error": "에러 메시지"
        }
    """
    try:
        # 빈 텍스트 체크
        if not text or text.strip() == "":
            return {
                "title": "내용 없음",
                "category": "unclassified",
                "department": DEPARTMENT_MAP["unclassified"],
                "confidence": 0.0,
                "success": False,
                "error": "분류할 텍스트가 비어있습니다."
            }

        # GPT-4o mini 호출 (temperature=0.0으로 일관된 결과 보장)
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.0,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": f"다음 민원을 분류해주세요:\n\n{text}"}
            ],
            response_format={"type": "json_object"}
        )

        # 응답 파싱
        result = json.loads(response.choices[0].message.content)

        # 유효성 검증
        category = result.get("category", "unclassified")
        if category not in CATEGORIES:
            category = "unclassified"

        title = result.get("title", "제목 없음")[:20]  # 20자 제한
        confidence = min(max(float(result.get("confidence", 0.0)), 0.0), 1.0)

        return {
            "title": title,
            "category": category,
            "department": DEPARTMENT_MAP.get(category, "민원봉사과"),
            "confidence": confidence,
            "success": True,
            "error": None
        }

    except json.JSONDecodeError:
        return {
            "title": "분류 실패",
            "category": "unclassified",
            "department": DEPARTMENT_MAP["unclassified"],
            "confidence": 0.0,
            "success": False,
            "error": "GPT 응답을 JSON으로 파싱할 수 없습니다."
        }
    except Exception as e:
        return {
            "title": "분류 실패",
            "category": "unclassified",
            "department": DEPARTMENT_MAP["unclassified"],
            "confidence": 0.0,
            "success": False,
            "error": f"NLP 분류 중 오류 발생: {str(e)}"
        }