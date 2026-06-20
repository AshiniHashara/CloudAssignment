alert_email    = "ashinihashara02@gmail.com"
admin_cidr     = "0.0.0.0/0"
ses_domain     = "cloudmart.internal"
ses_test_email = "ashinihashara02@gmail.com"

# This account's GuardDuty API is blocked (SubscriptionRequiredException on
# ListDetectors even with AdministratorAccess) — confirmed via AWS CLI
# pre-flight check. Flip to true on an account where GuardDuty is enabled.
enable_guardduty = false