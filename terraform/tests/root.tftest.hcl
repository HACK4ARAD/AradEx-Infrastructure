mock_provider "aws" {}
mock_provider "aws" {
  alias = "us_east_1"
}

run "invalid_email" {
  command = plan
  variables {
    alert_email = "nu-email"
  }
  expect_failures = [var.alert_email]
}

run "invalid_domain" {
  command = plan
  variables {
    alert_email = "a@b.ro"
    domain_name = "nu un domeniu"
  }
  expect_failures = [var.domain_name]
}

run "invalid_count" {
  command = plan
  variables {
    alert_email       = "a@b.ro"
    api_desired_count = 3
  }
  expect_failures = [var.api_desired_count]
}

run "defaults_ok" {
  command = plan
  variables {
    alert_email = "a@b.ro"
    domain_name = ""
  }
  assert {
    condition     = var.github_owner == "HACK4ARAD" && var.backend_repo == "AradEx-Backend" && var.frontend_repo == "AradEx-Frontend"
    error_message = "repo defaults"
  }
  assert {
    condition     = var.branch == "main" && var.api_desired_count == 0 && var.domain_name == ""
    error_message = "branch/count/domain defaults"
  }
}

run "no_domain" {
  command = plan
  variables {
    alert_email = "a@b.ro"
    domain_name = ""
  }
  assert {
    condition     = length(module.edge) == 0 && length(module.web) == 0
    error_message = "edge and web only with a domain"
  }
}

run "with_domain" {
  command = plan
  variables {
    alert_email       = "a@b.ro"
    domain_name       = "aradex.example"
    api_desired_count = 1
  }
  assert {
    condition     = length(module.edge) == 1 && length(module.web) == 1
    error_message = "edge and web exist with a domain"
  }
}
