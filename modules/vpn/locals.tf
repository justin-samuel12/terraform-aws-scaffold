locals {
  ike_versions          = ["ikev2"]
  encryption_algorithms = ["AES256", "AES256-GCM-16"]
  integrity_algorithms  = ["SHA2-256", "SHA2-384", "SHA2-512"]
  dh_groups             = [14, 19, 20, 21]
}
