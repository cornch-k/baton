# Baton

Claude Code용 에이전트 릴레이 루프입니다. 모델과 관점이 서로 다른 서브에이전트들이 매 턴 새로 떠서 레포를 통해 바통을 넘깁니다. flame chase, ralph 루프, 리뷰가 붙은 루프, 계획 후 구현, 점수 기반 병렬 레인, 재귀 Lean 증명기, flow 작성기까지 들어 있습니다.

[English README](README.md)

## 왜 필요한가

에이전트 하나에게 다 맡기지 않는 편이 나은 작업이 있습니다.

- **새 세션은 레포를 정직하게 만듭니다.** 다음 에이전트가 기억 없이 시작하면 파일에 없는 건 사라지므로, 파일 자체가 좋아야 합니다.
- **에이전트마다 실패하는 방식이 다릅니다.** 매 턴이 남이 쓴 작업을 점검하는 데서 시작하면, 한 에이전트의 맹점이 쌓이지 않습니다.
- **"끝났다"는 판단은 작업한 당사자가 하면 안 됩니다.** 작업 과정을 못 본 리뷰어가 실제로 있는 것만 보고 판단합니다.

[Humanize](https://github.com/humanfia/humanize) 같은 도구는 Claude, Codex 등 여러 회사의 에이전트를 섞어서 이 다양성을 얻습니다. Baton은 Claude Code 안에서 **모델과 관점이 둘 다 다른 서브에이전트**로 같은 효과를 냅니다. 기본값은 chaser A가 Opus·구현자(builder), chaser B가 Sonnet·회의적 검증자(skeptic)이고, 둘 다 설정에서 바꿀 수 있습니다.

## 설치

```text
/plugin marketplace add cornch-k/baton
/plugin install baton@baton
```

설치하지 않고 로컬 체크아웃으로 써 보려면:

```bash
claude --plugin-dir /path/to/baton
```

## Flow 목록

| 명령 | 하는 일 |
|---|---|
| `/baton:flame-chase "<작업>"` | 모델·관점이 다른 두 chaser가 번갈아 작업합니다. 매 턴 새 서브에이전트이고, 둘 사이에 넘어가는 건 작업 공간뿐입니다 |
| `/baton:cleanup-flame-chase "<작업>"` | flame-chase에 몇 턴마다 정리 에이전트가 붙습니다. 찌꺼기 제거, 짧은 `NEXT.md`, 에포크마다 커밋 하나로 합치기(옛 기록은 태그로 보존) |
| `/baton:ralph-loop "<작업>"` | 매 라운드 새 worker에게 같은 작업을 줍니다. 이어지는 건 레포뿐입니다 |
| `/baton:cleanup-ralph "<작업>"` | ralph-loop에 정리 에이전트를 붙인 것입니다 |
| `/baton:stateful-ralph "<작업>"` | 세션을 유지하는 worker 하나에게 매 라운드 같은 작업을 줍니다 |
| `/baton:continue-loop "<작업>"` | 작업을 한 번 주고, 그다음부터는 "continue"만 보냅니다 |
| `/baton:goal "<목표>"` | 작업을 worker 자신의 목표로 줍니다. 목표를 달성했다고 근거와 함께 말하면 멈춥니다 |
| `/baton:rlar "<작업>"` | 세션을 유지하는 actor가 일하고, 매번 새로 뜨는 리뷰어가 완료 여부를 판단하고 다음 지시를 씁니다 |
| `/baton:gen-idea "<아이디어>"` | 아이디어를 주 방향과 대안이 담긴 초안으로 만듭니다. 레포와 대조하고, 코드는 쓰지 않습니다 |
| `/baton:gen-plan <아이디어>` | 기억을 유지하는 planner와 매번 새로 뜨는 analyst가 `docs/plan.md`에 합의합니다 |
| `/baton:rlcr [docs/plan.md]` | 계획을 구현합니다. 매 턴 정지 검사, 매 라운드 새 리뷰, 마지막에 전체 변경 리뷰가 깨끗해야 끝납니다 |
| `/baton:fixed-interrupt "<작업>" --eval "<명령>"` | 평가 명령으로 채택된 실험 k개마다 chaser가 교대합니다. 마지막에 블라인드 리뷰어가 승자를 고릅니다 |
| `/baton:parallel-chase "<작업>"` | coordinator가 서로 다른 레인 3개를 계획하고, 레인마다 병렬로 chase합니다. 리더보드를 공유합니다 |
| `/baton:parallel-chase-pr "<작업>" --eval "<명령>"` | 레인 3개가 후보를 제안하고, 깨끗한 체크아웃에서 잰 점수가 오를 때만 병합합니다 |
| `/baton:recursive-lean-prover "<정리>"` | Lean 4 정리를 보조정리로 쪼갭니다. 보조정리마다 먼저 Lean으로 바로 증명해 보고, 안 될 때만 산문 증명, 단계별 검토, 분할을 거칩니다. 워크트리에서 형식화하고 위키에 기록합니다. Lean이 계획한 명제와 정확히 같음을 확인하고 `#print axioms`에 `sorryAx`나 추가 공리가 없을 때만 받아들입니다. Lake 프로젝트와 elan으로 설치한 Lean이 필요합니다(`brew install elan-init`) |
| `/baton:author-flow "<설명>"` | 설명대로 새 flow를 씁니다. 로드 검사, 가짜 세계 종료 검사, 비평가를 모두 통과해야 들어갑니다 |

`/baton:flows`로 목록을 보고 고를 수 있습니다.

공통 플래그: `--turns N`, `--minutes M`, `--check "<명령>"`, `--no-early-stop`, `--in-place`, `--resume [run-id]`.

## 실행 방식

1. git 레포이고 작업 트리가 깨끗해야 합니다. 실행용 브랜치 `baton/<flow>-<시각>`을 만들고, 원래 브랜치는 건드리지 않습니다.
2. 메인 세션이 **오케스트레이터**입니다. 매 턴 서브에이전트를 띄우고, flow가 허용한 것만 넘깁니다(대부분 작업 공간뿐). 턴이 끝나면 `scripts/baton.sh`를 한 번 불러서 커밋, 검사, 기록, 예산 확인을 한꺼번에 합니다.
3. 에이전트는 턴 끝에 짧은 `BATON-REPORT`(리뷰어는 `BATON-VERDICT`)를 남깁니다. 오케스트레이터는 이 블록만 들고 있어서 자기 컨텍스트가 오래 갑니다.
4. 실행 상태는 `.baton/runs/<run-id>/`에 저장됩니다(`.git/info/exclude`에 등록되어 작업 트리에 섞이지 않음): `state.json`, `log.md`, 검사·평가 로그.
5. 끝나면 멈춘 이유, 커밋 목록, 브랜치를 병합·삭제하거나 이어서 실행하는 명령을 알려 줍니다.

Baton은 push하지 않고, 사용자 브랜치에 병합하지 않으며, 권한 우회 모드를 켜지 않습니다. 긴 실행은 버려도 되는 레포에서 `acceptEdits`나 `auto` 권한 모드로 돌리는 걸 권합니다.

## 비용

매 턴 새 에이전트가 작업 공간을 다시 읽습니다. 이게 설계의 핵심이고, 실행 비용도 대부분 여기서 나옵니다. Baton은 그 밖의 비용을 작게 유지합니다.

- 일하는 에이전트는 도구를 6개(Read, Write, Edit, Bash, Glob, Grep)만 가집니다. 세션의 모든 도구와 MCP 서버를 싣지 않으므로, 요청마다 고정으로 드는 컨텍스트가 33k~50k 토큰에서 약 9k로 줄어듭니다. 에이전트는 한 턴에 요청을 수십 번 보냅니다. 웹·MCP 도구는 없지만 Bash로 `curl`은 쓸 수 있습니다.
- 오케스트레이터의 기록 작업은 턴마다 스크립트 호출 한 번입니다. 커밋, 검사, 로그, 예산 확인마다 모델이 왕복하지 않습니다.
- Lean 보조정리는 산문 증명·검토·분할 전에 먼저 Lean으로 바로 증명해 봅니다. Lean의 기계적 확인을 리뷰어가 다시 돌리지도 않습니다.

같은 2턴 flame chase로 재 보니, 0.2.0은 0.1.1보다 서브에이전트 입력 토큰을 59~67%(전체로는 37%) 덜 썼고, 85초 대신 65~68초에 끝났습니다.

가장 큰 조절 장치는 설정입니다. Chaser A와 worker 기본값이 Opus인데, `sonnet`으로 바꾸면 훨씬 적게 듭니다. `--turns`는 작게 시작하세요. 조기 종료는 기본으로 켜져 있습니다.

## 설정

`/plugin` → baton → configure, 또는 `/config`의 baton 항목에서 바꿉니다.

| 설정 | 기본값 | 선택지 |
|---|---|---|
| Chaser A 모델 / 관점 | `opus` / `builder` | `opus`, `sonnet`, `haiku`, `fable` / `builder`, `skeptic`, `simplifier`, `tester` |
| Chaser B 모델 / 관점 | `sonnet` / `skeptic` | 같음 |
| Worker 모델 | `opus` | 같은 모델들 |
| Reviewer 모델 | `sonnet` | 같은 모델들 |
| 기본 턴 예산 | `8` | 1–200 |

## 원본 flow와 다른 점

- 에이전트는 별도 CLI 세션이나 다른 회사 모델이 아니라 Claude Code 서브에이전트입니다. 다양성은 모델과 관점의 조합에서 나옵니다.
- 대부분의 flow는 자체 완료 조건이 맞으면 일찍 멈춥니다(`--no-early-stop`을 주면 원본처럼 예산 끝까지 돕니다).
- `parallel-chase-pr`는 GitHub PR을 여는 대신 로컬 병합 후보를 씁니다.
- `author-flow`의 종료 검사는 가짜 에이전트로 실제 실행하지 않고, 리뷰어 모델이 단계별로 추적합니다.
- `rlcr`의 정지 검사는 자체 6종입니다(검사 명령, 충돌 표시, 새 스텁, 건너뛴 테스트, 비밀값, 계획 파일 무변경).

## 출처

flow 설계는 [Humanfia의 flows](https://humanfia.ai/flows/), [Humanize](https://github.com/humanfia/humanize), PolyArch/humanize에서 아이디어를 얻었습니다. Baton은 독립적으로 다시 구현한 것이며 그 프로젝트들의 코드나 프롬프트 문구를 포함하지 않습니다. Humanfia, PolyArch와 관계가 없습니다. [NOTICE](NOTICE)를 참고하세요.

## 라이선스

[Apache-2.0](LICENSE)
