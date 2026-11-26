# Instalar observabilidade em VM dedicada

Esta etapa instala uma stack didática de observabilidade em uma VM Linux separada do cluster Kubernetes. A VM fica fora do cluster para reduzir a competição por CPU, memória e disco com os nós usados nos exercícios e para manter os dados de diagnóstico disponíveis quando o cluster estiver indisponível.

O desenho usa Fluent Bit nos nós Kubernetes para coletar logs de containers e encaminhá-los via OTLP ao Collector incluído no ClickStack na VM. A aplicação instrumentada também envia telemetria ao Collector via OTLP. O ClickStack armazena e permite consultar os sinais no ClickHouse e HyperDX. A retenção é curta, de poucos dias, suficiente para fins didáticos.

## Recursos e arquitetura

Dimensione a VM de observabilidade com:

- **6 GB de RAM**;
- **aproximadamente 20 GB de disco**, com armazenamento persistente para os dados;
- rede/IP acessível pelos nós Kubernetes e pela aplicação, sem expor portas de ingestão à rede pública.

A capacidade é para uma carga pequena de laboratório. A retenção curta ajuda a limitar o uso do disco; acompanhe o espaço livre e reduza o período caso o armazenamento cresça mais rápido que o esperado.

| Origem | Coleta/recepção | Destino | Sinal |
| --- | --- | --- | --- |
| Nós Kubernetes | Fluent Bit, instalado como DaemonSet no cluster | OpenTelemetry Collector na VM | Logs de containers |
| Aplicação `podinfo` | Instrumentação OpenTelemetry nativa | OpenTelemetry Collector na VM via OTLP/gRPC | Traces; logs seguem pelo Fluent Bit e métricas ficam disponíveis no endpoint Prometheus `/metrics` |
| Collector | Pipelines de logs, métricas e traces | ClickStack na VM | Telemetria para consulta no HyperDX e armazenamento no ClickHouse |

Fluent Bit encaminha os logs ao Collector; não configure um segundo envio paralelo desses mesmos logs diretamente ao armazenamento. Mantenha os endpoints OTLP acessíveis apenas pela rede do laboratório e ajuste firewall para permitir somente as origens necessárias.

## 12.1 Preparar a VM

Crie uma VM Linux fora do cluster, reservando 6 GB de RAM e cerca de 20 GB de disco. Use um IP estável na rede do laboratório. Aplique atualizações do sistema e confirme conectividade entre a VM e os nós Kubernetes:

```bash
ip -brief address
ping -c 3 <IP_DE_UM_WORKER>
```

Registre endereço, distribuição e versão do sistema operacional. Reserve o disco para os dados persistentes da stack e confirme que há espaço livre suficiente antes de instalar.

## 12.2 Instalar ClickStack (ClickHouse, HyperDX e Collector OTLP)

Para este laboratório, use a distribuição oficial **All-in-One** em um único contêiner Docker. Ela inclui ClickHouse para armazenar a telemetria, HyperDX para consulta e visualização, MongoDB para estado da interface e um OpenTelemetry Collector configurado para ingestão OTLP. Portanto, não instale um segundo Collector nesta VM: Fluent Bit e a aplicação enviarão dados ao Collector incluído no ClickStack.

Os comandos abaixo pressupõem Ubuntu Server 22.04/24.04 x86-64. Execute-os na VM de observabilidade. Para outra distribuição, use o método de instalação do Docker Engine recomendado para ela.

### Instalar Docker Engine e o plugin Compose

Atualize o sistema e instale os pacotes necessários para configurar o repositório oficial do Docker:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

Adicione o repositório estável para a arquitetura da VM:

```bash
. /etc/os-release
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
```

Instale e habilite Docker Engine e o plugin Compose:

```bash
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

Para executar Docker sem prefixar os comandos com `sudo`, adicione o usuário da VM que fará a instalação ao grupo `docker`:

```bash
sudo usermod -aG docker "$USER"
```

A alteração de grupos só vale em uma nova sessão. Encerre a sessão SSH e conecte-se novamente, ou reinicie a VM. Então valide o acesso sem `sudo`:

```bash
groups
docker version
docker compose version
```

A saída de `groups` deve incluir `docker`, e os comandos de versão devem funcionar sem erro. Se ainda houver `permission denied`, confirme que está numa sessão nova e que o daemon está ativo com `sudo systemctl status docker`.

> **Atenção:** membros do grupo `docker` podem controlar o daemon com privilégios equivalentes a `root`. Faça isso somente para um usuário confiável da VM. A partir daqui, os comandos Docker deste guia podem ser executados sem `sudo` pelo usuário incluído no grupo.

### Preparar diretório e configuração

Crie um diretório de trabalho e os diretórios persistentes exigidos pela distribuição All-in-One. O Docker poderá criar arquivos como `root`; mantenha o diretório sob controle de `root`. Os exemplos abaixo usam `sudo` para os comandos Docker caso a sessão ainda não tenha sido renovada; após entrar novamente, remova esse prefixo se o usuário já estiver no grupo `docker`:

```bash
sudo mkdir -p /opt/clickstack/.volumes/{db,ch_data,ch_logs}
cd /opt/clickstack
```

Crie `/opt/clickstack/compose.yaml` usando `sudo tee` para gravar como `root`:

```bash
sudo tee /opt/clickstack/compose.yaml >/dev/null <<'EOF
services:
  clickstack:
    image: clickhouse/clickstack-all-in-one:latest
    container_name: clickstack
    restart: unless-stopped
    environment:
      # Substitua pelo IP estável da VM, acessível pelo navegador no Windows.
      FRONTEND_URL: "http://<IP_DA_VM>:8080"
    ports:
      - "8080:8080" # interface HyperDX
      - "4317:4317" # OTLP gRPC
      - "4318:4318" # OTLP HTTP
    volumes:
      - ./.volumes/db:/data/db
      - ./.volumes/ch_data:/var/lib/clickhouse
      - ./.volumes/ch_logs:/var/log/clickhouse-server
EOF
```

Antes de iniciar o contêiner, substitua `<IP_DA_VM>` em `FRONTEND_URL` pelo IP estável real da VM (por exemplo, `192.168.50.20`). Use exatamente a mesma URL para abrir a interface no navegador do Windows. Se já iniciou a stack antes de alterar essa variável, recrie o serviço para aplicar a configuração:

```bash
cd /opt/clickstack
docker compose up -d --force-recreate
```

A imagem `latest` facilita o primeiro uso, mas pode mudar entre atualizações. Depois de validar o laboratório, registre a versão/tag usada; antes de atualizar, consulte as notas da versão e faça cópia dos dados que deseja preservar. Os volumes mantêm o estado ao recriar ou reiniciar o contêiner, mas não substituem backup.

### Iniciar e conferir os serviços

Baixe a imagem e inicie o ClickStack:

```bash
cd /opt/clickstack
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
```

Acompanhe a inicialização. Na primeira execução, alguns componentes podem demorar para ficar prontos:

```bash
sudo docker compose logs --tail=100 -f
```

Interrompa o acompanhamento com `Ctrl+C`; isso não para os contêineres. Para verificar posteriormente:

```bash
sudo docker compose ps
sudo docker compose logs --tail=100 clickstack
```

Abra `http://<IP_DA_VM>:8080` no navegador do Windows e faça login. O `FRONTEND_URL` define a URL pública usada pelo HyperDX em redirecionamentos; se ficar no padrão `localhost`, o navegador do Windows tentará abrir a própria máquina Windows após o login, em vez da VM. No formulário de primeiro acesso, use as credenciais didáticas:

- **Usuário:** `lab@k8s.local`
- **Senha:** `Lab-k8s-kubernetes`

No primeiro acesso, a interface cria as fontes de dados para o ClickHouse integrado. Essas credenciais são destinadas somente ao laboratório; mantenha a interface e as portas publicadas protegidas pela rede e pelo firewall.

### Restringir acesso às portas

Permita acesso à porta `8080` somente a partir da máquina de administração (por exemplo, `sre-tools`). Permita `4317` e `4318` somente das origens que enviarão telemetria: os nós para Fluent Bit e a rede/origem da aplicação. Não crie regras de encaminhamento dessas portas no roteador e não as exponha à internet.

Se o UFW estiver ativo, substitua os endereços pelos IPs reais antes de executar. Repita uma regra de ingestão por cada origem necessária:

```bash
sudo ufw allow from <IP_DA_MAQUINA_ADMIN> to any port 8080 proto tcp
sudo ufw allow from <IP_DE_UM_WORKER> to any port 4317 proto tcp
sudo ufw allow from <IP_DE_UM_WORKER> to any port 4318 proto tcp
sudo ufw status numbered
```

Se os Pods usarem endereços de rede diferentes dos nós, crie também regras para o CIDR de Pods apenas quando necessário e compatível com a política da rede. Não libere o CIDR inteiro sem confirmar a origem efetiva do tráfego.

### Confirmar acesso e persistência

Da máquina autorizada, abra a interface HyperDX. Na VM, confirme que as portas estão em escuta e que o contêiner continua ativo:

```bash
sudo docker compose ps
sudo ss -lntp | grep -E ':(8080|4317|4318)\b'
```

As portas `4317` e `4318` correspondem à ingestão OTLP gRPC e HTTP. Use uma delas por agente conforme o protocolo configurado. Os diretórios `db`, `ch_data` e `ch_logs` em `/opt/clickstack/.volumes` guardam estado da interface, dados do ClickHouse e logs do banco. Confirme o crescimento e espaço livre:

```bash
df -h /opt/clickstack
sudo du -sh /opt/clickstack/.volumes/*
```

Pare e inicie a stack sem remover o volume:

```bash
cd /opt/clickstack
sudo docker compose stop
sudo docker compose start
```

Para atualizar a imagem, consulte as notas da versão e salve os dados antes. `docker compose down` remove o contêiner e a rede do Compose, mas preserva esses diretórios bind-mounted. **Não use `docker compose down -v` nem remova `.volumes`** se quiser preservar dados.

> A instalação All-in-One é apropriada para demonstração e laboratório, não para produção: todos os componentes compartilham um contêiner e recursos, e os diretórios persistentes não são um backup. Com 6 GB de RAM e cerca de 20 GB de disco, mantenha ingestão baixa, retenção curta e monitore o espaço. A retenção deve ser configurada conforme a documentação de TTL do ClickStack; confirme as tabelas e a política efetiva para logs, métricas e traces depois da instalação.

## 12.3 Instalar Fluent Bit via Helm em `sre-tools`

A instalação é administrada a partir da VM `sre-tools`, onde estão configurados `kubectl` e Helm. O Fluent Bit roda no cluster, como DaemonSet, com um Pod em cada nó para ler os logs locais dos containers e encaminhá-los ao Collector do ClickStack na VM de observabilidade.

### Conferir o acesso ao cluster e obter a chave de ingestão

Execute todos os comandos desta seção em `sre-tools`. Confirme o contexto e que os três nós estão `Ready`:

```bash
kubectl config current-context
kubectl get nodes -o wide
helm version
```

No HyperDX, abra **Team Settings → API Keys** e copie a chave de ingestão do ClickStack. Ela será enviada no header HTTP `authorization` pelo Fluent Bit. Trate-a como segredo: não a publique nem a versione no Git. O endpoint OTLP/HTTP do ClickStack é `http://<IP_DA_VM>:4318/v1/logs`.

### Criar os valores do chart

Adicione o repositório oficial do chart Fluent Bit e atualize o índice:

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update
```

Crie `fluent-bit-values.yaml` em `sre-tools`. Substitua `<IP_DA_VM>` pelo endereço estável da VM de observabilidade e `<CHAVE_DE_INGESTAO>` pela chave copiada do HyperDX. Não faça commit desse arquivo; ele contém a chave em texto claro.

```yaml
config:
  service: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Parsers_File  /fluent-bit/etc/parsers.conf
        Parsers_File  /fluent-bit/etc/conf/custom_parsers.conf
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020
        Health_Check  On
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        multiline.parser  docker, cri
        Tag               kube.*
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
        Read_from_Head    Off
  filters: |
    [FILTER]
        Name                kubernetes
        Match               kube.*
        Kube_Tag_Prefix     kube.var.log.containers.
        Merge_Log           On
        Keep_Log            Off
        K8S-Logging.Parser  On
        K8S-Logging.Exclude On
    # Exclui os próprios logs do Fluent Bit do fluxo enviado ao ClickStack.
    [FILTER]
        Name   grep
        Match  kube.*
        Exclude $kubernetes['pod_name'] ^fluent-bit-
  outputs: |
    [OUTPUT]
        Name                opentelemetry
        Match               kube.*
        Host                <IP_DA_VM>
        Port                4318
        TLS                 Off
        Logs_URI            /v1/logs
        Header              authorization <CHAVE_DE_INGESTAO>
```

O input lê os logs de containers em `/var/log/containers`; o filtro consulta a API Kubernetes para enriquecer os registros com metadados de Pod e namespace e, em seguida, descarta os registros cujo Pod começa com `fluent-bit-`; o output envia o restante via OTLP/HTTP para ClickStack. O chart oficial instala como DaemonSet e monta os diretórios de logs do nó. A chave aparece no ConfigMap renderizado pelo Helm, portanto esse arquivo e o acesso ao cluster devem ser tratados como confidenciais no laboratório.

O Fluent Bit também escreve mensagens operacionais em `stdout`/`stderr`. Como o input acompanha os logs de todos os containers, mensagens como `output:opentelemetry ... HTTP status=200` (exportação bem-sucedida) e `input:tail ... inotify_fs_add()` (início do monitoramento de um arquivo) podem aparecer no HyperDX se os logs do próprio agente não forem filtrados. Elas são diagnósticos do coletor, não logs da aplicação. O filtro acima evita enviá-las; se forem úteis durante uma investigação, remova temporariamente essa exclusão e depois aplique a configuração novamente.

### Instalar ou atualizar o release

Instale o chart no namespace `observability`:

```bash
helm upgrade --install fluent-bit fluent/fluent-bit \
  --namespace observability \
  --create-namespace \
  --values fluent-bit-values.yaml
```

Aguarde o DaemonSet ficar pronto e confira se há um Pod em cada nó:

```bash
kubectl rollout status daemonset/fluent-bit -n observability --timeout=5m
kubectl get daemonset,pods -n observability -o wide
```

O número desejado de Pods do DaemonSet deve corresponder aos nós elegíveis. Se algum nó não tiver Pod, examine taints e eventos antes de alterar tolerations.

### Validar encaminhamento

Confira os logs do agente e procure erros de conexão, autenticação ou exportação:

```bash
kubectl logs -n observability -l app.kubernetes.io/name=fluent-bit --all-containers=true --tail=100
kubectl get events -n observability --sort-by=.metadata.creationTimestamp
```

Gere algumas requisições para `podinfo` e confirme no HyperDX que aparecem logs dos containers, com campos de namespace, Pod e container. Se houver `401`/`403`, confira a chave de ingestão; se houver timeout, confira IP, firewall e acesso dos nós à porta `4318` da VM. Corrija o arquivo de valores e aplique novamente o `helm upgrade --install`.

Para remover somente este release em uma manutenção deliberada, execute em `sre-tools` `helm uninstall fluent-bit -n observability`; isso interrompe a coleta dos logs do cluster. Não remova o namespace inteiro se outros recursos de observabilidade estiverem nele.

## 12.4 Configurar `podinfo` para enviar traces ao Collector

O chart oficial do `podinfo` aceita argumentos adicionais em `extraArgs` e variáveis em `extraEnvs`. Para ativar a telemetria desta versão, é necessário definir o argumento `--otel-service-name=podinfo`; sem ele, o próprio `podinfo` desativa tracing e exportação de logs OTLP. A variável genérica `OTEL_SERVICE_NAME` não substitui esse argumento, pois o `podinfo` lê essa opção como configuração própria. Com o argumento e o endpoint OTLP definidos, o app exporta traces. Os logs de texto continuam sendo coletados pelo Fluent Bit. As métricas disponíveis em `/metrics` são Prometheus; esta configuração não as envia como métricas OTLP.

Execute os comandos em `sre-tools`. Primeiro, crie no namespace `lab-sre` um Secret com a chave de ingestão do ClickStack obtida em **HyperDX → Team Settings → API Keys**. O valor precisa ser `authorization=<chave>`. O comando não imprime o conteúdo do Secret:

```bash
read -rsp 'Chave de ingestao do ClickStack: ' CLICKSTACK_INGESTION_KEY
echo
kubectl create secret generic clickstack-otel \
  --namespace lab-sre \
  --from-literal="otel-headers=authorization=${CLICKSTACK_INGESTION_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset CLICKSTACK_INGESTION_KEY
```

Crie `podinfo-otel-values.yaml` em `sre-tools`, substituindo `<IP_DA_VM>` pelo IP estável da VM de observabilidade:

```yaml
extraArgs:
  - --otel-service-name=podinfo

extraEnvs:
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: grpc
  - name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
    value: http://<IP_DA_VM>:4317
  - name: OTEL_EXPORTER_OTLP_HEADERS
    valueFrom:
      secretKeyRef:
        name: clickstack-otel
        key: otel-headers
```

A porta `4317` recebe OTLP/gRPC no Collector do ClickStack. A variável `OTEL_EXPORTER_OTLP_HEADERS` fornece a chave exigida pelo endpoint. Não acrescente `/v1/traces` ao endpoint gRPC; esse caminho é usado por OTLP/HTTP na porta `4318`.

Atualize a release existente usando os valores originais da etapa 10 e este arquivo adicional. O Helm combina os dois arquivos e os valores de telemetria acrescentam configuração sem remover o NodePort e as duas réplicas:

```bash
helm upgrade --install podinfo podinfo/podinfo \
  --namespace lab-sre \
  --values podinfo-values.yaml \
  --values podinfo-otel-values.yaml \
  --wait --timeout 5m
```

Confirme o rollout e que as variáveis foram adicionadas ao template do Deployment sem imprimir a chave do Secret:

```bash
kubectl rollout status deployment/podinfo -n lab-sre --timeout=5m
kubectl get pods -n lab-sre -o wide
kubectl describe deployment podinfo -n lab-sre
```

Gere requisições para criar traces e pesquise no HyperDX pela fonte **Traces**, filtrando o serviço `podinfo` e o intervalo de tempo atual:

```bash
for i in {1..10}; do
  curl -sS -o /dev/null http://<IP_DE_UM_WORKER>:31198/
done
```

Se ainda não aparecerem traces, faça estas verificações em ordem:

1. Confirme que o Deployment recebeu as variáveis e referência ao Secret sem exibir o valor secreto:

   ```bash
   kubectl get deployment podinfo -n lab-sre -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{"\n"}{end}'
   kubectl describe deployment podinfo -n lab-sre
   ```

   Confirme em `describe` que `Command`/`Args` inclui `--otel-service-name=podinfo` e que `Environment` lista `OTEL_EXPORTER_OTLP_PROTOCOL`, `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` e `OTEL_EXPORTER_OTLP_HEADERS`. Confirme também que `OTEL_EXPORTER_OTLP_HEADERS` aponta para `clickstack-otel`, chave `otel-headers`.

2. Gere spans com um endpoint HTTP de aplicação e confira que respondeu:

   ```bash
   curl -i http://<IP_DE_UM_WORKER>:31198/status/200
   ```

3. Confira a conectividade TCP entre a rede dos Pods e a VM na porta `4317`. A regra de firewall precisa aceitar o endereço de origem que a VM realmente vê; ele pode ser o IP de um nó ou o CIDR de Pods, dependendo do caminho da rede.

4. Na VM de observabilidade, veja os logs do ClickStack no mesmo intervalo e procure erros OTLP/autenticação:

   ```bash
   cd /opt/clickstack
   sudo docker compose logs --since=10m clickstack 2>&1 | grep -Ei '401|403|unauthor|error|otlp|trace'
   ```

5. Se aparecer `401`/`403`, confira se o Secret contém a **API ingestion key** atual de **Team Settings → API Keys**. Se a chave foi rotacionada, recrie o Secret e aplique novamente o upgrade Helm para provocar o rollout. Se houver timeout, verifique endpoint, firewall e rota. Se a conexão chegar sem erro mas não houver dados, confira no HyperDX a fonte **Traces**, o serviço `podinfo` e o intervalo de tempo.

A chave não deve ser copiada para `podinfo-otel-values.yaml` nem impressa em saídas compartilhadas.

## 12.5 Validar a ingestão e a retenção

Valide em sequência:

1. O Collector está ativo e recebendo telemetria, sem erros de exportação ou descartes por limite de memória.
2. Fluent Bit está pronto em cada nó e os logs de containers aparecem no ClickStack/HyperDX.
3. A aplicação gera e envia sinais OTLP; confirme os dados disponíveis no HyperDX.
4. Os registros têm atributos de serviço, namespace, Pod e container suficientes para filtrar e correlacionar.
5. A retenção está configurada para poucos dias e o volume de dados cabe no disco de aproximadamente 20 GB.
6. O uso de RAM, disco e CPU da VM não interfere nos recursos do cluster.

Repita o exercício [11 — recuperação de um Pod](11_exercicio_recuperacao_pod.md) e consulte a janela correspondente no HyperDX. Registre o que ocorreu antes e depois da remoção, a chegada do Pod substituto e eventuais erros ou latência observados.

## Cuidados operacionais

- A VM fica fora do cluster para preservar recursos dos nós e manter diagnóstico independente do cluster.
- Retenção e volume de ingestão afetam diretamente o disco; acompanhe espaço livre e reduza a retenção se necessário.
- A exclusão de recursos Kubernetes usados pelo Fluent Bit interrompe a coleta nos nós. Confirme o namespace e o contexto antes de alterar ou remover esses recursos.
- Não use `helm uninstall`, `kubectl delete` em recursos da aplicação ou `kubeadm reset` como método de limpeza desta etapa.
- Para pausar a stack, pare os serviços da VM de forma controlada. Preserve o volume persistente se quiser manter dados dos exercícios.

## Referências

- [Chart Helm oficial do podinfo](https://github.com/stefanprodan/podinfo/tree/master/charts/podinfo)
- [Inicialização do OpenTelemetry no podinfo](https://github.com/stefanprodan/podinfo/blob/master/cmd/podinfo/main.go)
- [Ingestão OTLP no ClickStack](https://clickhouse.com/docs/clickstack/ingesting-data/opentelemetry)
- [Configuração de endpoints OTLP](https://opentelemetry.io/docs/specs/otel/protocol/exporter/)
- [Fluent Bit](https://docs.fluentbit.io/manual/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [ClickStack All-in-One](https://clickhouse.com/docs/clickstack/deployment/install/all-in-one)
- [Gerenciar retenção (TTL) no ClickStack](https://clickhouse.com/docs/clickstack/manage/ttl)
- [Instalar Docker Engine no Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

