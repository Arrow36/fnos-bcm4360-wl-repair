PYTHON ?= python3
DRIVER ?=

.PHONY: build verify check clean

build:
	$(PYTHON) scripts/build_fpk.py $(if $(DRIVER),--driver "$(DRIVER)",)

verify:
	$(PYTHON) scripts/verify_fpk.py

check: build verify
	bash -n src/fnos-bcm4360-oneclick.sh

clean:
	@echo "请手工删除明确的 dist/ 和 .cache/ 目录；本项目不提供递归清理命令。"
