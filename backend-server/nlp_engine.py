# NLP 분류 엔진 - GPT-4o mini를 사용한 민원 자동 분류
import os
import json
from openai import AsyncOpenAI
from dotenv import load_dotenv
from messages import NlpMessages
from database import get_supabase

load_dotenv()
# [Fix #7] AsyncOpenAI 클라이언트로 전환 (async 함수 내 동기 호출 블로킹 방지)
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# 민원 분류 카테고리 정의
CATEGORIES = {
    "repair": "파손/수리 — 시설물 파손, 도로 파손, 가로등 고장 등",
    "suggestion": "건의사항 — 정책 건의, 환경 개선 등",
    "inquiry": "문의사항 — 행정 절차 문의, 서비스 이용 방법 등",
    "permission": "허가/신고 — 불법 건축 신고, 시설 사용 허가 등",
    "unclassified": "미분류 — 내용이 모호하거나 판단이 어려운 경우"
}

# 부서 매칭 테이블 (기본값 설정용 - DB에 없을 경우 대비)
DEPARTMENT_MAP = {
    "repair": "road",
    "suggestion": "planning",
    "inquiry": "civil",
    "permission": "building",
    "unclassified": "civil"
}

async def get_dynamic_system_prompt() -> tuple[str, list[str]]:
    """
    DB에서 부서 목록을 가져와 동적 시스템 프롬프트 생성
    """
    try:
        supabase = get_supabase()
        res = await supabase.table("departments").select("key, label, keywords").order("id").execute()
        depts = res.data or []
    except Exception as e:
        print(f"[nlp] Failed to fetch depts for prompt: {e}")
        depts = []

    # 부서 정보 텍스트 생성
    if depts:
        dept_info = ""
        allowed_depts = []
        for d in depts:
            key = d.get("key")
            label = d.get("label")
            keywords = ", ".join(d.get("keywords", [])) if d.get("keywords") else "관련 업무"
            dept_info += f"- {key}: {label} ({keywords})\n"
            allowed_depts.append(key)
    else:
        # Fallback (DB 조회 실패 시)
        dept_info = """- road: 도로과 (도로 파손, 포트홀, 보도블럭, 아스팔트, 신호등 고장 등)
- building: 건축과 (건물, 옥상, 벽, 불법건축, 공사장 불편 등)
- park: 녹지공원과 (공원 관리, 나무, 가로수, 잔디, 화단 등)
- traffic: 교통과 (불법 주차, 교통 체증, 버스/택시 민원, 신호 체계 등)
- environment: 환경과 (쓰레기 무단투기, 악취, 폐기물, 소음, 먼지 등)
- planning: 기획예산과 (정책 제안, 예산 반영, 제도 개선 건의 등)
- civil: 민원담당관 (기타 일반 민원, 위 부서들에 해당하지 않는 경우)"""
        allowed_depts = ["road", "building", "park", "traffic", "environment", "planning", "civil"]

    allowed_depts_str = "|".join(allowed_depts)

    prompt = f"""당신은 춘천시 민원 분류 AI 시스템입니다.
시민의 민원 내용을 분석하여 아래 부서, 카테고리, 그리고 민원 유형(현장/행정) 중 하나로 정확히 분류하고, 요약된 제목을 만들어주세요.

## 민원 유형 (complaint_type)
- field: 현장 민원 (특정 장소에 직접 방문하여 물리적 작업이나 조사가 필요한 민원. 예: 도로 파손, 가로등 고장, 쓰레기 무단투기 등)
- admin: 행정 민원 (서류 처리, 시스템 증명서 발급, 단순 문의, 정책 제안 등 현장 조사가 불필요한 민원)

## 담당 부서 (department)
{dept_info}

## 분류 카테고리 (category)
- repair: 파손/수리 (물리적 보수 필요)
- suggestion: 건의사항 (제안, 환경 개선 요청 등)
- inquiry: 문의사항 (단순 질문, 절차 확인 등)
- permission: 허가/신고 (불법 신고, 인허가 관련)

## 응답 형식 (반드시 JSON으로만 답변)
{{
    "title": "20자 이내의 간결한 민원 제목",
    "complaint_type": "field|admin",
    "category": "repair|suggestion|inquiry|permission",
    "department": "{allowed_depts_str}",
    "confidence": 0.0~1.0 사이의 분류 신뢰도
}}

주의사항:
- 반드시 유효한 JSON만 출력하세요.
- title은 20자 이내로 핵심만 요약하세요.
- 확신이 없으면 department를 "civil"로, category를 "inquiry"로, complaint_type을 "admin"으로 설정하세요.
"""
    return prompt, allowed_depts


async def classify_complaint(text: str) -> dict:
    """
    STT 텍스트를 받아 GPT-4o mini로 민원 분류

    Args:
        text: STT로 변환된 민원 텍스트
    
    Returns:
        {
            "title": "요약된 민원 제목",
            "complaint_type": "field|admin",
            "category": "repair|suggestion|inquiry|permission|unclassified",
            "department": "...",
            "confidence": 0.95,
            "success": True/False,
            "error": "에러 메시지"
        }
    """
    try:
        # 빈 텍스트 체크
        if not text or text.strip() == "":
            return {
                "title": NlpMessages.DEFAULT_TITLE,
                "complaint_type": "admin",
                "category": "unclassified",
                "department": "civil",
                "confidence": 0.0,
                "success": False,
                "error": NlpMessages.EMPTY_TEXT
            }

        # 동적 프롬프트 생성
        system_prompt, allowed_depts = await get_dynamic_system_prompt()

        # GPT-4o mini 호출 (temperature=0.0으로 일관된 결과 보장)
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.0,
            messages=[
                {"role": "system", "content": system_prompt},
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

        dept = result.get("department", "civil")
        # 지원하지 않는 부서 키일 경우 fallback
        if dept not in allowed_depts:
            dept = "civil" if "civil" in allowed_depts else (allowed_depts[0] if allowed_depts else "civil")

        title = result.get("title", "제목 없음")[:20]  # 20자 제한
        complaint_type = result.get("complaint_type", "field")
        if complaint_type not in ["field", "admin"]:
            complaint_type = "field"
            
        confidence = min(max(float(result.get("confidence", 0.0)), 0.0), 1.0)

        return {
            "title": title,
            "complaint_type": complaint_type,
            "category": category,
            "department": dept,
            "confidence": confidence,
            "success": True,
            "error": None
        }

    except json.JSONDecodeError:
        return {
            "title": NlpMessages.FAILED_TITLE,
            "category": "unclassified",
            "department": DEPARTMENT_MAP["unclassified"],
            "confidence": 0.0,
            "success": False,
            "error": NlpMessages.JSON_PARSE_ERROR
        }
    except Exception as e:
        return {
            "title": NlpMessages.FAILED_TITLE,
            "category": "unclassified",
            "department": DEPARTMENT_MAP["unclassified"],
            "confidence": 0.0,
            "success": False,
            "error": NlpMessages.PROCESSING_ERROR.format(error=str(e))
        }