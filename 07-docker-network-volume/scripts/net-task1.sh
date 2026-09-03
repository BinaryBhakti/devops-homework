#!/bin/bash
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
sec() { echo; echo "==================================================="; echo "  $*"; echo "==================================================="; }

# ---- clean slate ----
docker rm -f frontend backend database >/dev/null 2>&1
docker network rm frontend-net backend-net mgmt-net >/dev/null 2>&1

sec "0. Docker's default networks"
run "docker network ls"
echo "-- bridge = default for containers, host = share the host stack, none = no networking --"

sec "1. CREATE 3 USER-DEFINED BRIDGE NETWORKS"
run "docker network create frontend-net"
run "docker network create backend-net"
run "docker network create mgmt-net"
run "docker network ls --filter driver=bridge"
echo "-- User-defined bridges give you automatic DNS: containers resolve each other BY NAME. --"
run "docker network inspect frontend-net --format '{{.Name}} -> subnet {{range .IPAM.Config}}{{.Subnet}}{{end}} gateway {{range .IPAM.Config}}{{.Gateway}}{{end}}'"
run "docker network inspect backend-net  --format '{{.Name}} -> subnet {{range .IPAM.Config}}{{.Subnet}}{{end}} gateway {{range .IPAM.Config}}{{.Gateway}}{{end}}'"
run "docker network inspect mgmt-net     --format '{{.Name}} -> subnet {{range .IPAM.Config}}{{.Subnet}}{{end}} gateway {{range .IPAM.Config}}{{.Gateway}}{{end}}'"

sec "2. START THE DATABASE (MySQL) on backend-net ONLY"
run "docker run -d --name database --network backend-net \
      -e MYSQL_ROOT_PASSWORD=rootpass \
      -e MYSQL_DATABASE=appdb \
      -e MYSQL_USER=appuser \
      -e MYSQL_PASSWORD=apppass \
      mysql:8.0"

sec "3. START THE FRONTEND (Nginx) on frontend-net ONLY"
run "docker run -d --name frontend --network frontend-net nginx:alpine"

sec "4. START THE BACKEND (Alpine) on frontend-net, then ATTACH it to backend-net"
echo "-- A container can only be given ONE network with 'docker run --network'. --"
echo "-- Additional networks are added afterwards with 'docker network connect'. --"
run "docker run -d --name backend --network frontend-net alpine:latest sleep infinity"
run "docker network connect backend-net backend"
echo "-- backend is now on TWO networks: --"
run "docker inspect backend --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}} = {{\$v.IPAddress}}{{println}}{{end}}'"

sec "5. WHO IS ON WHICH NETWORK?"
run "docker network inspect frontend-net --format 'frontend-net: {{range .Containers}}{{.Name}}({{.IPv4Address}}) {{end}}'"
run "docker network inspect backend-net  --format 'backend-net : {{range .Containers}}{{.Name}}({{.IPv4Address}}) {{end}}'"
run "docker network inspect mgmt-net     --format 'mgmt-net    : {{range .Containers}}{{.Name}}({{.IPv4Address}}) {{end}}'"
cat <<'DIAGRAM'
    +--------------------+                      +--------------------+
    |   frontend-net     |                      |    backend-net     |
    |                    |                      |                    |
    |  [frontend]        |                      |        [database]  |
    |       \            |                      |          /         |
    |        \___ [ backend ] ___________________________/           |
    |            (on BOTH networks - the only bridge between them)   |
    +--------------------+                      +--------------------+

    +--------------------+
    |     mgmt-net       |   created but empty - proves networks are
    |     (empty)        |   independent, isolated broadcast domains
    +--------------------+
DIAGRAM

sec "6. INSTALL NETWORK TOOLS IN THE TEST CONTAINERS"
run "docker exec backend sh -c 'apk add --no-cache curl bind-tools mysql-client >/dev/null 2>&1; echo tools installed'"
run "docker exec frontend sh -c 'apk add --no-cache curl bind-tools >/dev/null 2>&1; echo tools installed'"

sec "7. CONNECTIVITY TEST: frontend  ->  backend   (SAME network: frontend-net)"
run "docker exec frontend ping -c 3 backend"
run "docker exec frontend nslookup backend"
echo "-- Name resolution works because they share a user-defined bridge. --"

sec "8. CONNECTIVITY TEST: backend  ->  frontend   (SAME network: frontend-net)"
run "docker exec backend ping -c 3 frontend"
run "docker exec backend curl -s -o /dev/null -w 'HTTP %{http_code} from frontend nginx\n' http://frontend"

sec "9. CONNECTIVITY TEST: backend  ->  database   (SAME network: backend-net)"
run "docker exec backend ping -c 3 database"
run "docker exec backend nslookup database"

sec "10. THE KEY TEST -- frontend  ->  database   (NO shared network)"
echo "-- frontend is on frontend-net; database is on backend-net. --"
echo "-- They share NO network, so this MUST fail: --"
run "docker exec frontend ping -c 2 -W 2 database"
run "docker exec frontend nslookup database"
echo "-- Isolation confirmed. Only 'backend' can reach the database. --"
echo "-- This is exactly how you protect a database in a real deployment. --"
