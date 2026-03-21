# Gateway-Proxy — Workspace Instructions

Discord Gateway WebSocket 프록시. 클라이언트 재시작 시 다운타임 제로를 달성하기 위해 Discord와의 연결을 유지하고 이벤트를 릴레이한다.

## Build & Run

```bash
# Nightly Rust 필수 (rust-src 컴포넌트 필요)
cargo build --release --target=x86_64-unknown-linux-gnu

# SIMD 비활성화 빌드
cargo build --release --no-default-features --features no-simd

# Docker (권장)
docker build --build-arg TARGET_CPU=haswell -t gateway-proxy .
docker run --rm -it -v /path/to/config.json:/config.json gateway-proxy
```

실행 시 CWD에 `config.json` 필요. 예시: [config.example.json](../config.example.json)

## Lint & Format

```bash
cargo clippy --target=x86_64-unknown-linux-gnu   # pedantic + nursery 수준
cargo fmt -- --check
```

CI에서 `clippy`와 `rustfmt` 모두 통과해야 한다. 테스트 스위트는 없음.

## Architecture

```
src/
├── main.rs          # 엔트리포인트, 샤드 생성, 시그널 핸들링
├── config.rs        # config.json 로딩, LazyLock 전역 CONFIG, inotify 핫리로드
├── server.rs        # HTTP/WS 서버, IDENTIFY/RESUME 처리, zlib 압축, /metrics 엔드포인트
├── state.rs         # 전역 상태 (Ready, Shard, Inner), 세션 관리
├── dispatch.rs      # Discord→프록시 이벤트 루프, 캐시 업데이트, broadcast 전파
├── cache.rs         # twilight-cache-inmemory 래퍼, 가짜 READY/GUILD_CREATE 생성
├── deserializer.rs  # 경량 JSON 스캐너 (바이트 위치 기반 시퀀스 번호 치환)
├── model.rs         # Discord 페이로드 모델 (Identify, Resume, Ready 등)
└── upgrade.rs       # HTTP→WebSocket 업그레이드, RFC6455 핸드셰이크
```

**이벤트 흐름:** 프록시가 모든 샤드를 Discord에 연결 → 클라이언트가 IDENTIFY 전송 → 해당 샤드의 broadcast 채널 구독 → 캐시 기반 가짜 READY 전송 → 이벤트 릴레이

## Key Conventions

- **Clippy 수준:** `#![deny(clippy::pedantic, clippy::nursery)]` — 엄격한 린트. 허용된 예외는 [main.rs](../src/main.rs) 상단 참조
- **rustfmt:** `imports_granularity = "crate"` — 같은 크레이트의 import를 하나의 `use`문으로 병합
- **Feature flags:** `simd` (기본) vs `no-simd` — `#[cfg(feature = "simd-json")]` 조건부 컴파일이 코드 전반에 존재
- **에러 처리:** `tracing::error!/warn!`으로 로깅 후 `continue` 패턴. 서버 크래시 방지 우선
- **전역 상태:** `LazyLock<Config>` (`CONFIG`), `AtomicBool` (`SHUTDOWN`)
- **Import 순서:** 외부 크레이트 → 표준 라이브러리 → `crate::` 내부 모듈
- **릴리스 프로필:** `codegen-units = 1`, `lto = true`, `panic = "abort"` — 최대 성능

## Pitfalls

- **Nightly 전용:** `tokio-websockets`의 `nightly` feature와 SIMD 최적화로 nightly 컴파일러 필수
- **커스텀 Twilight fork:** `Gelbpunkt/twilight` branch `0.16` 사용 — 업스트림과 호환 불가
- **Linux 전용:** `inotify` 기반 config 핫리로드는 macOS/Windows 미지원
- **unsafe 사용:** `simd_json::from_str`의 `&mut String` 요구, `unwrap_unchecked()` 등 — 수정 시 주의
- **시퀀스 번호 치환:** `deserializer.rs`가 JSON을 파싱하지 않고 바이트 위치로 `replace_range` 수행 — Discord JSON 구조 변경 시 깨질 수 있음
- **config.json 경로 하드코딩:** CWD 기준 `config.json` 고정

## Dependencies

핵심 외부 의존성:
- **twilight** (커스텀 fork): gateway, http, model, cache-inmemory
- **tokio + hyper 1.x**: 비동기 런타임 + HTTP 서버
- **tokio-websockets**: WebSocket (nightly + SIMD)
- **simd-json / serde_json**: JSON 파싱 (feature flag 전환)
- **flate2**: zlib 압축
- **mimalloc**: 글로벌 메모리 할당자
- **metrics + metrics-exporter-prometheus**: Prometheus 메트릭
