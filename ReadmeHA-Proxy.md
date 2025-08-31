| Service              | Subdomain                               | Port                                  |
| -------------------- | --------------------------------------- | ------------------------------------- |
| Open WebUI           | `openwebui.ha.valuechainhackers.xyz`    | 8080                                  |
| n8n                  | `n8n.ha.valuechainhackers.xyz`          | 5678                                  |
| Flowise              | `flowise.ha.valuechainhackers.xyz`      | 3001              |
| Langfuse             | `langfuse.ha.valuechainhackers.xyz`     | 3000                                  |
| SearXNG              | `search.ha.valuechainhackers.xyz`       | 8080                                  |
| Qdrant (UI/API)      | `qdrant.ha.valuechainhackers.xyz`       | 6333                                  |
| Neo4j Browser        | `neo4j.ha.valuechainhackers.xyz`        | 7474 (+7687 Bolt if you need drivers) |
| Supabase Studio      | `supabase.ha.valuechainhackers.xyz`     | 3000                                  |
| Supabase API Gateway | `supabase-api.ha.valuechainhackers.xyz` | 8000                                  |


94.142.240.28

Route Domain

  acl host_openwebui hdr(host) -i openwebui.ha.valuechainhackers.xyz
  acl host_n8n       hdr(host) -i n8n.ha.valuechainhackers.xyz
  acl host_flowise   hdr(host) -i flowise.ha.valuechainhackers.xyz
  acl host_langfuse  hdr(host) -i langfuse.ha.valuechainhackers.xyz
  acl host_search    hdr(host) -i search.ha.valuechainhackers.xyz
  acl host_qdrant    hdr(host) -i qdrant.ha.valuechainhackers.xyz
  acl host_neo4j     hdr(host) -i neo4j.ha.valuechainhackers.xyz
  acl host_supabase  hdr(host) -i supabase.ha.valuechainhackers.xyz
  acl host_supabase_api hdr(host) -i supabase-api.ha.valuechainhackers.xyz

  use_backend bk_openwebui if host_openwebui
  use_backend bk_n8n       if host_n8n
  use_backend bk_flowise   if host_flowise
  use_backend bk_langfuse  if host_langfuse
  use_backend bk_search    if host_search
  use_backend bk_qdrant    if host_qdrant
  use_backend bk_neo4j     if host_neo4j
  use_backend bk_supabase  if host_supabase
  use_backend bk_supabase_api if host_supabase_api

backend bk_openwebui
  server s1 127.0.0.1:8080 check

backend bk_n8n
  server s1 127.0.0.1:5678 check

backend bk_flowise
  server s1 127.0.0.1:3000 check

backend bk_langfuse
  server s1 127.0.0.1:3000 check

backend bk_search
  server s1 127.0.0.1:8080 check

backend bk_qdrant
  server s1 127.0.0.1:6333 check

backend bk_neo4j
  server s1 127.0.0.1:7474 check

backend bk_supabase
  server s1 127.0.0.1:3000 check

backend bk_supabase_api
  server s1 127.0.0.1:8000 check
