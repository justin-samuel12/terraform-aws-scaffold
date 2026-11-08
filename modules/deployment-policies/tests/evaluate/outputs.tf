output "decisions" {
  description = "Request name -> allow, deny (an explicit Deny matched), implicit-deny (no Allow matched), or unsupported (a condition operator this model does not evaluate)."
  value       = local.decisions
}

output "allowed" {
  description = "Request name -> true when the request is allowed."
  value       = { for name, d in local.decisions : name => d == "allow" }
}

output "matched" {
  description = "Request name -> the statements that matched it, as policy/Sid, to explain a decision."
  value       = { for name, list in local.evaluated : name => [for s in list : "${s.policy}/${s.sid} ${s.effect}" if s.hit] }
}
