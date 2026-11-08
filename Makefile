# Thin convenience wrapper: every target calls ./run.sh, which is the canonical entry point.
.DEFAULT_GOAL := help
RUN := ./run.sh

.PHONY: monitor help up doctor tools setup deploy verify demo status logs report test validate cleanup

help:      ## list targets
	@$(RUN) help

up:        ## everything: cluster -> Terraform -> Argo CD -> release -> verify -> report
	@$(RUN) up
doctor:    ## check prerequisites (read-only)
	@$(RUN) doctor
tools:     ## install missing CLI tools into ~/.local/bin
	@$(RUN) tools
setup:     ## cluster + Terraform + Argo CD + monitoring
	@$(RUN) setup
deploy:    ## test, build, scan, SBOM, push, commit digest to Git
	@$(RUN) deploy
verify:    ## end-to-end release verification
	@$(RUN) verify
demo:      ## bad release + Git rollback demonstration
	@$(RUN) demo
status:    ## overview + access URLs
	@$(RUN) status
logs:      ## follow application logs
	@$(RUN) logs app
report:    ## build the JSON + Markdown release report
	@$(RUN) report
test:      ## Maven tests
	@$(RUN) test
validate:  ## offline lint/validate (helm, terraform, shell)
	@$(RUN) validate
cleanup:   ## delete only this project's cluster, registry and state
	@$(RUN) cleanup
monitor:   ## prove dashboards/alerts/Grafana work
	@$(RUN) monitor
