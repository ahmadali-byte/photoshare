import os
from azure.ai.vision.imageanalysis import ImageAnalysisClient
from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.ai.textanalytics import TextAnalyticsClient
from azure.core.credentials import AzureKeyCredential

_vision_client: ImageAnalysisClient | None = None
_language_client: TextAnalyticsClient | None = None


def _get_vision() -> ImageAnalysisClient:
    global _vision_client
    if _vision_client is None:
        _vision_client = ImageAnalysisClient(
            endpoint=os.environ["VISION_ENDPOINT"],
            credential=AzureKeyCredential(os.environ["VISION_KEY"]),
        )
    return _vision_client


def _get_language() -> TextAnalyticsClient:
    global _language_client
    if _language_client is None:
        _language_client = TextAnalyticsClient(
            endpoint=os.environ["LANGUAGE_ENDPOINT"],
            credential=AzureKeyCredential(os.environ["LANGUAGE_KEY"]),
        )
    return _language_client


def analyze_image(image_bytes: bytes) -> dict:
    """Returns AI-generated tags and caption for a photo."""
    try:
        client = _get_vision()
        result = client.analyze(
            image_data=image_bytes,
            visual_features=[VisualFeatures.TAGS, VisualFeatures.CAPTION],
        )
        tags = [t.name for t in (result.tags.list if result.tags else [])]
        description = (
            result.caption.text if result.caption else "No description available"
        )
        return {"tags": tags[:10], "description": description}
    except Exception as e:
        return {"tags": [], "description": f"Analysis unavailable: {str(e)}"}


def analyze_sentiment(text: str) -> dict:
    """Returns sentiment label and confidence score for comment text."""
    try:
        client = _get_language()
        response = client.analyze_sentiment([text])
        doc = response[0]
        if doc.is_error:
            return {"sentiment": "neutral", "score": 0.5}
        label = doc.sentiment
        scores = doc.confidence_scores
        score_map = {"positive": scores.positive, "negative": scores.negative, "neutral": scores.neutral}
        return {
            "sentiment": label,
            "score": round(score_map.get(label, 0.5), 3),
        }
    except Exception:
        return {"sentiment": "neutral", "score": 0.5}
