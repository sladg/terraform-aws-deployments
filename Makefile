docs:
	@echo "Generating documentation..."
	terraform-docs markdown table --output-file README.md --output-mode inject ./modules/standalone
	terraform-docs markdown table --output-file README.md --output-mode inject ./modules/export
	@echo "Documentation generated successfully!"

lint:
	@echo "Linting Terraform code..."
	tflint --recursive
	@echo "Terraform code linted successfully!"