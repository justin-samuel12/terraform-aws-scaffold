locals {
  # Security and critical fixes, for each operating system we run.
  baselines = {
    windows = {
      operating_system = "WINDOWS"
      filters          = { CLASSIFICATION = ["SecurityUpdates", "CriticalUpdates"], MSRC_SEVERITY = ["Critical", "Important"] }
    }
    amazon-linux-2023 = {
      operating_system = "AMAZON_LINUX_2023"
      filters          = { CLASSIFICATION = ["Security", "Bugfix"], SEVERITY = ["Critical", "Important"] }
    }
    ubuntu = {
      operating_system = "UBUNTU"
      filters          = { PRIORITY = ["Required", "Important"] }
    }
  }
}
