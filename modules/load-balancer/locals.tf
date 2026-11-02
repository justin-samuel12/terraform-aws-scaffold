locals {

  # AWS allows 32 characters. The suffix comes from everything AWS cannot change in place, so a new port or protocol builds a new group first.
  target_group_names = {
    for target, t in var.targets : target => (
      length("${var.name}-${target}") <= 23
      ? "${var.name}-${target}-${substr(sha1("${var.name}/${target}/${t.port}/${t.protocol}"), 0, 8)}"
      : "${substr("${var.name}-${target}", 0, 23)}-${substr(sha1("${var.name}/${target}/${t.port}/${t.protocol}"), 0, 8)}"
    )
  }
}
