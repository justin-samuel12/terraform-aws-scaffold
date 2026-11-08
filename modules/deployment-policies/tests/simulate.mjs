import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { runSimulation } from '@cloud-copilot/iam-simulate'
import { iamActionDetails, iamActionExists, iamResourceTypeDetails } from '@cloud-copilot/iam-data'

const [folder, requestsFile, sharedFile] = process.argv.slice(2)
const load = (name, env = 'staging') => JSON.parse(readFileSync(join(folder, `${env}-${name}.json`), 'utf8'))
const administrator = { Version: '2012-10-17', Statement: [{ Effect: 'Allow', Action: '*', Resource: '*' }] }
const keyPolicy = (account) => ({ Version: '2012-10-17', Statement: [{ Effect: 'Allow', Principal: { AWS: `arn:aws:iam::${account}:root` }, Action: 'kms:*', Resource: '*' }] })

let failures = 0
let warnings = 0
const counts = { refused: 0, allowed: 0 }

for (const [env, file] of [['staging', requestsFile], ['shared', sharedFile]]) {
 for (const [group, entries] of Object.entries(JSON.parse(readFileSync(file, 'utf8')))) {
  for (const [name, r] of Object.entries(entries)) {
    const boundaryOnly = r.policies.length === 1 && r.policies[0].startsWith('boundary-')
    const principalAccount = r.resource.includes(':111111111111:') || r.policies[0] === 'network-role' ? '111111111111' : '222222222222'
    const simulation = {
      request: {
        principal: `arn:aws:iam::${principalAccount}:role/deployed/principal`,
        action: r.action,
        resource: { resource: r.resource, accountId: principalAccount },
        contextVariables: r.context ?? {},
      },
      identityPolicies: boundaryOnly
        ? [{ name: 'administrator', policy: administrator }]
        : r.policies.map((p) => ({ name: p, policy: load(p, env) })),
      permissionBoundaryPolicies: boundaryOnly ? [{ name: r.policies[0], policy: load(r.policies[0], env) }] : undefined,
      serviceControlPolicies: [],
      resourceControlPolicies: [],
      resourcePolicy: r.action.startsWith('kms:') && r.resource.includes(':key/') ? keyPolicy(principalAccount) : undefined,
    }
    const response = await runSimulation(simulation, {})
    if (response.resultType === 'error') {
      console.log(`FAIL  ${group} ${name}: the simulator refused the request: ${JSON.stringify(response.errors).slice(0, 400)}`)
      failures++
      continue
    }
    const result = response.overallResult ?? response.result?.analysis?.result ?? response.result?.result
    const allowed = result === 'Allowed'
    counts[group]++
    if (allowed !== (group === 'allowed')) {
      console.log(`FAIL  ${group} ${name}: the simulator says ${result}`)
      failures++
    }
  }
 }
}

const checked = ['aws:ResourceTag/', 'aws:RequestTag/', 'aws:TagKeys', 'iam:PermissionsBoundary', 'iam:PolicyARN', 's3:if-none-match', 'ec2:CreateAction', 'kms:ViaService']
const seen = new Set()
let pairs = 0
const documents = [
  ...['read', 'plan', 'propose', 'network-role', 'dns-read-role', ...['network', 'workload', 'services', 'iam'].flatMap((d) => [d, `${d}-state`, `${d}-limits`, `${d}-environment`, `${d}-ownership`, `boundary-${d}`])].map((f) => [f, 'staging']),
  ...['read', 'plan', 'propose', ...['hub', 'services', 'iam'].flatMap((d) => [d, `${d}-state`, `${d}-limits`, `${d}-environment`, `${d}-ownership`, `boundary-${d}`])].map((f) => [f, 'shared']),
]
for (const [file, env] of documents) {
  for (const s of load(file, env).Statement) {
    if (!s.Condition || !s.Action) continue
    const actions = [s.Action].flat().filter((a) => !a.includes('*'))
    const keys = Object.values(s.Condition).flatMap((k) => Object.keys(k)).filter((k) => checked.some((c) => k.startsWith(c)))
    for (const action of actions) {
      const [service, name] = action.split(':')
      if (!(await iamActionExists(service, name))) {
        console.log(`FAIL  ${file}/${s.Sid}: ${action} is not an AWS action`)
        failures++
        continue
      }
      const details = await iamActionDetails(service, name)
      const types = await Promise.all((details.resourceTypes ?? []).filter((t) => t.name).map((t) => iamResourceTypeDetails(service, t.name.replace('*', ''))))
      const available = new Set([...(details.conditionKeys ?? []), ...(details.resourceTypes ?? []).flatMap((t) => t.conditionKeys ?? []), ...types.flatMap((t) => t.conditionKeys ?? [])].map((k) => k.toLowerCase().replace(/\$\{tagkey\}/, '')))
      for (const key of keys) {
        const generic = key.toLowerCase().replace(/(aws:(resourcetag|requesttag)\/).*/, '$1')
        const id = `${action} ${generic}`
        if (seen.has(id)) continue
        seen.add(id)
        pairs++
        if (!available.has(generic)) {
          const mustHave = s.Effect === 'Allow' || Object.entries(s.Condition).some(([op, k]) => op === 'Null' && k[key] === 'true')
          console.log(`${mustHave ? 'FAIL' : 'WARN'}  ${file}/${s.Sid}: ${action} does not support ${key}`)
          if (mustHave) failures++
          else warnings++
        }
      }
    }
  }
}

console.log(`iam-simulate: ${counts.refused} refused and ${counts.allowed} allowed requests decided; ${pairs} action and condition key pairs checked against AWS's published data; ${warnings} warnings; ${failures} failures`)
process.exit(failures === 0 ? 0 : 1)
