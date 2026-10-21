// The one module that imports node:dns. It supplies the Resolver used by the
// resolver-backed UrlPolicy. Kept separate so tests never import it.

import { promises as dnsPromises } from "node:dns"
import { nodeResolver, type Resolver } from "./policy.ts"

/** Every A and AAAA address for a name, via dns.lookup with all: true. NXDOMAIN is a failure. */
export const systemResolver: Resolver = nodeResolver((hostname) => dnsPromises.lookup(hostname, { all: true }))
