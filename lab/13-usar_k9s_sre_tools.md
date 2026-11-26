# Usar o k9s na VM `sre-tools`

Esta etapa instala o `k9s`, uma interface de terminal para navegar e operar o cluster com menos digitação que o `kubectl`. O `k9s` não tem configuração própria de acesso: ele usa o mesmo kubeconfig e o mesmo contexto do `kubectl`.

Execute os comandos em `sre-tools`. Pré-requisitos: etapa [9 — configurar acesso ao cluster](9-configurar_acesso_cluster_sre_tools.md) concluída, com o `kubectl` funcionando, e de preferência a etapa [10 — instalar o podinfo](10_instalar_podinfo.md), para ter Pods para explorar.

## 13.1 Conferir o acesso do `kubectl`

Antes de instalar, confirme que o `kubectl` conecta e qual contexto está ativo:

```bash
kubectl config current-context
kubectl get nodes
```

O contexto esperado é `k8s-lab-admin` e os três nós devem aparecer `Ready`. Se o `kubectl` falhar, o `k9s` também vai falhar; corrija o acesso pela etapa 9 antes de continuar.

## 13.2 Instalar o `k9s`

Baixe o binário da última versão publicada no GitHub (arquitetura amd64) e instale em `/usr/local/bin`:

```bash
cd /tmp
curl -sLO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
tar -xzf k9s_Linux_amd64.tar.gz k9s
sudo install -m 0755 k9s /usr/local/bin/k9s
rm -f k9s k9s_Linux_amd64.tar.gz
k9s version
```

O `sudo` é necessário apenas para gravar em `/usr/local/bin`. Para atualizar no futuro, repita os mesmos comandos.

## 13.3 Abrir e conectar

```bash
k9s
```

O `k9s` lê `~/.kube/config` ou o arquivo indicado na variável `KUBECONFIG`, exatamente como o `kubectl`. Opções úteis:

```bash
k9s -n lab-sre                       # abre direto no namespace do podinfo
k9s --kubeconfig /caminho/config     # usa outro kubeconfig
k9s --context k8s-lab-admin          # força um contexto específico
k9s --readonly                       # desativa ações que alteram o cluster
```

O cabeçalho mostra o contexto, o cluster e o usuário em uso. Se o nome do cluster aparece ali, a conexão funcionou.

### Tela vazia ao abrir

O `k9s` abre na visão de Pods do namespace `default`, que neste laboratório não tem Pods. Por isso a lista aparece vazia mesmo com o cluster conectado. Para ver os Pods:

- Aperte `0` na tela de Pods para mostrar todos os namespaces.
- Ou digite `:ns`, escolha `lab-sre` e aperte `Enter`.

Se continuar vazio, compare com `kubectl get pods -A` e `kubectl config current-context`. Diferenças indicam que o `k9s` está usando outro kubeconfig ou outro contexto.

## 13.4 Comandos do dia a dia

**Navegação**

* `:pods` - lista os pods
* `:deploy` - lista os deployments
* `:svc` - lista os services
* `:nodes` - lista os nós do cluster
* `:ns` - lista os namespaces e troca de namespace
* `:events` - mostra os eventos do cluster
* `:ctx` - troca de contexto ou cluster
* `0` - mostra todos os namespaces
* `/texto` - filtra a lista
* `Esc` - volta ou limpa o filtro
* `?` - mostra todos os atalhos
* `:q` ou `ctrl-c` - sai do k9s

**Inspeção**

* `Enter` - abre o item, como os containers de um pod
* `d` - mostra o describe do recurso
* `y` - mostra o YAML
* `l` - mostra os logs
* `p` - mostra os logs do container anterior, útil depois de um restart
* `s` (nos logs) - liga ou desliga a rolagem automática
* `w` (nos logs) - liga ou desliga a quebra de linha
* `t` (nos logs) - mostra ou esconde o horário de cada linha

**Ações**

* `s` (em pods) - abre um shell no container
* `shift-f` - faz port-forward
* `e` - edita o recurso no editor definido em `EDITOR`
* `ctrl-d` - apaga o recurso, com confirmação
* `ctrl-k` - mata o pod sem confirmação
* `s` (em deployments) - escala as réplicas
* `r` (em deployments) - reinicia o rollout

**Visões úteis para SRE**

* `:pulses` - painel geral da saúde do cluster
* `:xray deploy` - árvore de dependências dos deployments
* `shift-c` / `shift-m` - ordena pods por CPU ou memória, se o Metrics Server estiver instalado

### Cuidado com ações destrutivas

`ctrl-d`, `ctrl-k`, `e`, `s` e `r` em deployments alteram o cluster na hora, como os comandos equivalentes do `kubectl`. Antes de usá-los, confira no cabeçalho o contexto e o namespace. Para só observar, abra com `k9s --readonly`.

## 13.5 Exercício rápido

Refaça o [exercício 11 — recuperação de Pod](11_exercicio_recuperacao_pod.md) pelo `k9s`:

1. Abra `k9s -n lab-sre` e vá para `:pods`.
2. Selecione um Pod do podinfo e apague com `ctrl-d`.
3. Observe o Deployment criar um Pod novo e a coluna `READY` voltar a `1/1`.
4. Em `:events`, veja a sequência de eventos da recuperação.

### Critério para avançar

- `k9s version` responde em `sre-tools`.
- O cabeçalho do `k9s` mostra o contexto `k8s-lab-admin`.
- Os Pods do namespace `lab-sre` aparecem com `0` ou `:ns`.
- Logs, describe e YAML de um Pod do podinfo abrem pelo `k9s`.

Referências: [documentação do k9s](https://k9scli.io/) e [releases do k9s no GitHub](https://github.com/derailed/k9s/releases).
