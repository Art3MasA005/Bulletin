"""Configuration. Single source for every model id, threshold, and dimension.

CLAUDE.md: "Config through pydantic-settings. No literals for models,
thresholds, or dimensions." If you find yourself typing a number into a
pipeline module, it belongs here instead.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class ConfigError(RuntimeError):
    """Raised when a required setting is missing, naming the env var to set."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(REPO_ROOT / ".env"),
        env_prefix="BULLETIN_",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ── OpenRouter ──────────────────────────────────────────────────────────
    # SecretStr, not str: a plain str prints in full in any pytest traceback,
    # log line, or crash report that happens to include the Settings object.
    # That is how keys leak from a private repo into a public CI log.
    openrouter_api_key: SecretStr = SecretStr("")
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    app_url: str = "https://github.com/yourname/bulletin"
    app_name: str = "Bulletin"
    # Attempts per request, including the first. A free-tier vision run meets
    # "temporarily rate-limited upstream" often enough that one attempt loses
    # pages to a transient 429.
    provider_max_retries: int = 4

    # Deliberately empty. See .env.example — the code refuses to guess a model
    # id, because a stale guess fails as an opaque 400 at request time.
    vision_model: str = ""
    generation_model: str = ""
    extraction_model: str = ""
    embedding_model: str = ""

    # Comma-separated model ids to try when the primary one is rate-limited or
    # unavailable. This exists because of a measured failure, not a hunch:
    # `qwen/qwen3.8-flash` is served by exactly ONE provider (Alibaba), so when
    # that provider's shared pool limits, OpenRouter has nowhere to route and
    # every retry waits on the same saturated queue. A model served by many
    # providers has no such single point of failure.
    #
    # Order matters — cheapest first. The fallback is tried immediately, with
    # no backoff, because switching model is faster than waiting for a pool
    # that is already full.
    generation_model_fallbacks: str = ""

    # ── Supabase (Phase 1+) ─────────────────────────────────────────────────
    # The anon key is safe in the Flutter client under RLS (PRD 6); the service
    # key and the database URL (which carries a password) are server-only and
    # must never be logged.
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_key: SecretStr = SecretStr("")
    # Only for projects created before Supabase moved to asymmetric JWT keys.
    # When set, tokens are verified as HS256 with this secret; when empty, the
    # project JWKS is used instead. Never sent anywhere.
    supabase_jwt_secret: SecretStr = SecretStr("")
    database_url: SecretStr = SecretStr("")

    # ── Ingestion (PRD §7.1, §10) ───────────────────────────────────────────
    max_upload_mb: int = 20
    max_pages: int = 150
    min_extracted_chars: int = 50
    bijoy_confidence_floor: float = 0.75
    # Below this text-layer quality score, a native_text page escalates to a
    # vision read (ingest/ocr_quality.py). Measured on the real corpus: prose
    # notices score 0.92-1.00, scanned exam-routine tables 0.53-0.82.
    ocr_quality_floor: float = 0.90
    scanned_chars_per_page: int = 60
    vision_render_dpi: int = 200

    # ── Chunking ────────────────────────────────────────────────────────────
    chunk_tokens_en: int = 600
    chunk_chars_bn: int = 1200
    chunk_overlap_ratio: float = 0.15

    # ── Retrieval (Phase 1) ─────────────────────────────────────────────────
    embedding_dim: int = 1024
    # Measured against the 57-question gold set, not guessed:
    # eval/reports/score_floor_probe.md. Answerable questions score 0.49-0.74,
    # unanswerable 0.41-0.56 -- the populations overlap, so no threshold is
    # clean. 0.48 keeps every answerable question and refuses 6 of 10
    # unanswerable ones before the LLM; the answer prompt catches the rest.
    retrieval_score_floor: float = 0.48
    retrieve_top_k: int = 20
    rerank_top_k: int = 5

    # Which cross-lingual strategy the pipeline runs (PRD §7.2, Ablation A).
    # "A" trusts the shared embedding space -- verified for baai/bge-m3 in
    # eval/reports/crosslingual_check.md. "B" additionally translates the
    # query and runs both arms again, buying back the lexical arm at the cost
    # of one round trip. A setting rather than a literal because the ablation
    # flips it; the default stays A until the ablation says otherwise.
    cross_lingual_strategy: str = "A"

    # ── Limits (PRD §10) ────────────────────────────────────────────────────
    # Free-tier preservation presented as friendly caps, not product decisions.
    questions_per_day: int = 50
    documents_per_institution: int = 200

    # ── Attachments (PRD §8.5) ──────────────────────────────────────────────
    attachment_max_mb: int = 10
    attachments_per_conversation: int = 3
    attachment_questions_per_day: int = 10
    attachment_image_ttl_days: int = 7
    extraction_confidence_floor: float = 0.9
    # Fan-out cap for the routine join: each confirmed course code is its own
    # retrieval round trip, so a thirty-line registration slip would turn one
    # question into thirty. Codes past the cap are reported, never dropped.
    join_max_codes: int = 12

    # ── Paths ───────────────────────────────────────────────────────────────
    corpus_dir: Path = Field(default=Path("corpus"))
    reports_dir: Path = Field(default=Path("eval/reports"))

    def resolved(self, p: Path) -> Path:
        return p if p.is_absolute() else REPO_ROOT / p

    @property
    def supabase_base_url(self) -> str:
        """Project base URL, with the Data API path removed if it was pasted in.

        The dashboard shows `https://<ref>.supabase.co/rest/v1/` on the Data
        API page and `https://<ref>.supabase.co` on the API page, and both look
        like "the project URL". Auth and Storage live at the base, so a pasted
        `/rest/v1/` silently sends every JWKS fetch to PostgREST, which answers
        404 with a PostgREST error code and no hint about what is wrong.
        """
        url = self.supabase_url.rstrip("/")
        for suffix in ("/rest/v1", "/auth/v1", "/storage/v1"):
            if url.endswith(suffix):
                url = url[: -len(suffix)]
        return url

    @property
    def generation_chain(self) -> list[str]:
        """The generation model, then its fallbacks, in the order to try them.

        Always starts with `generation_model`, so a misconfigured fallback list
        can degrade the answer but can never silently replace the model the
        evaluation numbers were measured on. Duplicates and blanks are dropped
        rather than retried.
        """
        chain = [self.require("generation_model")]
        for candidate in self.generation_model_fallbacks.split(","):
            model = candidate.strip()
            if model and model not in chain:
                chain.append(model)
        return chain

    @property
    def corpus_path(self) -> Path:
        return self.resolved(self.corpus_dir)

    @property
    def reports_path(self) -> Path:
        return self.resolved(self.reports_dir)

    def require(self, field: str) -> str:
        """Return a required setting or fail naming the env var to set.

        Unwraps SecretStr, so this is the ONLY place a secret becomes a plain
        string. Callers pass it straight to a request header and never log it.
        """
        value = getattr(self, field, "")
        if isinstance(value, SecretStr):
            value = value.get_secret_value()
        if not value:
            raise ConfigError(
                f"BULLETIN_{field.upper()} is not set. Add it to .env "
                f"(see .env.example). Model ids: https://openrouter.ai/models"
            )
        return str(value)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
