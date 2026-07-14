# Mding 빌드·릴리스 Makefile — 릴리스 파이프라인 본체는 scripts/release.sh

.DEFAULT_GOAL := help
.PHONY: help generate build test release clean

help:
	@echo "개발:"
	@echo "  make generate   Tuist 의존성 설치 + Xcode 프로젝트 생성"
	@echo "  make build      앱 빌드"
	@echo "  make test       단위 테스트"
	@echo "  make clean      릴리스 산출물 삭제"
	@echo ""
	@echo "릴리스:"
	@echo "  make release    scripts/release.sh 실행 (빌드→서명→DMG→공증→appcast→게시)"

generate:
	mise exec -- tuist install
	mise exec -- tuist generate --no-open

build: generate
	mise exec -- tuist build

test: generate
	mise exec -- tuist test

release:
	./scripts/release.sh

clean:
	rm -rf .release
