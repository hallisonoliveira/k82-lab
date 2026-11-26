# Adicionar os workers ao cluster

Esta etapa adiciona `k8s-worker01` e `k8s-worker02` ao cluster criado em `cp01`. O `kubeadm join` registra cada máquina como um nó; o kubelet e o Calico já instalados nela passam então a participar do cluster.

Execute os comandos de controle em `cp01` e os comandos de preparação e associação em cada worker. A etapa anterior deve estar concluída: Calico operacional, `cp01` `Ready`, CoreDNS `Running` e acesso administrativo ao cluster funcionando.

## 8.1 Conferir os pré-requisitos

Antes de associar os nós, confirme que os dois workers foram criados com os nomes definidos na proposta, têm IP estável e alcançam `cp01` pela rede do laboratório. Use SSH de `cp01` para cada worker e verifique também que os workers alcançam a API Kubernetes em `k8s-cp01:6443` (ou no endereço IP configurado para `cp01`). O nome `k8s-cp01` precisa resolver corretamente nos três nós.

Em cada worker, confirme:

- Ubuntu Server e arquitetura compatíveis com o control plane.
- `containerd` ativo e configurado com o driver de cgroups `systemd`.
- Swap desabilitado.
- `kubelet` e `kubeadm` instalados na mesma versão menor do control plane; neste laboratório, `v1.37.2`.
- Endereço IP estável da interface usada para tráfego do cluster.

Use os guias [3 — instalar containerd](3-instalar_containerd.md), [4 — desabilitar swap](4-desabilitar_swap.md) e [5 — instalar componentes Kubernetes](5-instalar_componentes_kubernetes.md) para preparar cada máquina. Confirme o endereço escolhido com `ip -br address` e a conectividade com `getent hosts k8s-cp01` e `nc -vz k8s-cp01 6443`.

No control plane, confirme o estado antes de prosseguir:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A
```

Não continue se Calico ou CoreDNS estiverem com falhas atuais. Um nó que não alcança a API ou que usa um endereço incorreto pode ficar `NotReady` após a associação.

## 8.2 Gerar o comando de associação

Em `cp01`, gere um token de bootstrap e o comando correspondente:

```bash
sudo kubeadm token create --print-join-command
```

O comando impresso terá esta forma:

```bash
sudo kubeadm join k8s-cp01:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

Copie o comando completo. O token é uma credencial temporária: não o grave no repositório, em scripts versionados ou em registros compartilhados. Por padrão, o token expira após 24 horas; se expirar, gere outro.

Se os workers tiverem mais de uma interface de rede, determine o endereço da interface de cluster em cada worker com `ip -br address`. Acrescente ao comando `kubeadm join` a opção `--node-ip=<IP_DO_WORKER>` para que o kubelet anuncie o endereço correto. Use o IP estável próprio de cada máquina.

## 8.3 Associar cada worker

Execute o comando gerado em `k8s-worker01` como `root` ou com `sudo`. Repita o procedimento em `k8s-worker02`, usando o mesmo token enquanto estiver válido e, se necessário, o respectivo `--node-ip`.

Exemplo ilustrativo — substitua o token, o hash e os IPs pelos valores gerados e configurados no seu ambiente:

```bash
sudo kubeadm join k8s-cp01:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --node-ip=<IP_DO_WORKER>
```

O processo baixa as imagens necessárias, configura o kubelet e solicita a entrada do nó no cluster. Aguarde a mensagem de sucesso no terminal de cada worker. Se falhar, investigue a mensagem antes de repetir: verifique DNS, rota, porta `6443`, relógio, versão dos pacotes e estado do containerd.

## 8.4 Validar os nós e a rede

Em `cp01`, acompanhe a entrada dos nós:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide -w
```

Interrompa a observação com `Ctrl+C` quando os três nós estiverem `Ready`. Em seguida, confira os Pods de sistema e do Calico:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide
```

Confirme que existe um Pod `calico-node` pronto em cada nó e que os Pods CoreDNS estão `Running`. Se um worker permanecer `NotReady`, inspecione suas condições e eventos:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf describe node <nome-do-worker>
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n calico-system -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -A \
  --sort-by=.metadata.creationTimestamp
```

No próprio worker, verifique o serviço e os logs do kubelet:

```bash
sudo systemctl status kubelet --no-pager
sudo journalctl -u kubelet -b --no-pager -n 100
```

Depois que ambos os workers estiverem `Ready`, teste a distribuição de uma aplicação de exemplo ou use o exercício da etapa seguinte. A associação bem-sucedida confirma o registro dos nós; a comunicação entre Pods em workers diferentes deve ser verificada por um teste de rede dedicado.

### Critério para avançar

- `k8s-cp01`, `k8s-worker01` e `k8s-worker02` aparecem como `Ready` em `kubectl get nodes -o wide`.
- O endereço `INTERNAL-IP` de cada worker corresponde à interface de cluster esperada.
- Calico tem um `calico-node` pronto em cada nó; CoreDNS está `Running`.
- Não há falhas atuais de kubelet ou eventos de rede que indiquem problema de conectividade.

## Troubleshooting

### Worker recém-associado permanece `NotReady`

Após `kubeadm join`, é esperado que o nó apareça primeiro como `NotReady` enquanto os DaemonSets de rede e os Pods locais iniciam. `calico-node` pode passar por várias etapas `Init` e `kube-proxy`/`csi-node-driver` podem aparecer como `ContainerCreating` durante esse período. Aguarde alguns minutos e acompanhe a transição:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide -w
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide -w
```

O status inicial, isoladamente, não indica falha. Se não houver progresso após alguns minutos, inspecione o Pod de rede agendado no worker e os eventos do nó:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf describe node k8s-worker01
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf describe pod \
  -n calico-system <calico-node-no-worker>
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -A \
  --sort-by=.metadata.creationTimestamp
```

Use o nome real do Pod retornado por `get pods -A -o wide`. Se uma etapa de init ou container mostrar erro, consulte seus logs:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf logs \
  -n calico-system <calico-node-no-worker> -c <container> --tail=100
```

No worker, confirme que o kubelet e o runtime estão ativos e consulte os logs recentes:

```bash
sudo systemctl status kubelet containerd --no-pager
sudo journalctl -u kubelet -b --no-pager -n 100
```

Não reinicie serviços nem faça `kubeadm reset` só porque o nó está em `NotReady` logo após o join. Primeiro identifique no `describe`/eventos se há erro de runtime, endereço de nó ou CNI.

#### Erro `exec: "runc": executable file not found in $PATH`

Se os eventos `FailedCreatePodSandBox` do worker incluem `exec: "runc": executable file not found in $PATH`, o kubelet está conseguindo registrar o nó, mas o containerd não consegue iniciar nenhum sandbox porque não encontra o runtime OCI `runc`. O aviso `cni plugin not initialized` em `describe node` é consequência: o Pod `calico-node` não consegue iniciar para configurar a rede.

No worker afetado, confira se `runc` está no `PATH` e se o serviço containerd registra erro de runtime:

```bash
command -v runc
runc --version
sudo journalctl -u containerd -b --no-pager -n 100
```

Se `runc` não estiver instalado, siga a seção 3.3 de [instalar containerd](3-instalar_containerd.md) para instalá-lo pelo repositório Ubuntu. Depois confirme que `command -v runc` retorna um caminho e que `runc --version` funciona. O containerd pode precisar ser reiniciado para reconhecer alterações em seus binários:

```bash
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

Reiniciar o containerd interrompe temporariamente os contêineres daquele nó. Faça isso apenas no worker afetado e espere os componentes serem recriados. Acompanhe do control plane:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide -w
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide -w
```

Espere `calico-node` e `kube-proxy` ficarem prontos e o worker passar a `Ready`. Não tente instalar CNI manualmente: a instalação do Calico via operador já fornece essa configuração quando seus Pods conseguem iniciar.

### O worker não alcança a API

No worker, confirme resolução do nome e conectividade TCP:

```bash
getent hosts k8s-cp01
nc -vz k8s-cp01 6443
ip route
```

Verifique a configuração DNS/hosts, o gateway, o firewall e se o endpoint em `kubeadm join` corresponde ao endpoint anunciado pelo control plane.

### O nó aparece com IP incorreto

Se a VM tem várias interfaces, o kubelet pode ter escolhido uma rota diferente. Confirme o IP com `kubectl get nodes -o wide` e compare com `ip -br address` no worker. Ajuste a configuração do kubelet para usar o endereço estável correto e reinicie o serviço somente após entender o impacto. Para uma nova associação, informe `--node-ip` no comando `kubeadm join`.

### O token expirou ou foi rejeitado

Gere outro comando em `cp01` com `sudo kubeadm token create --print-join-command`. Confira se a hora está sincronizada e copie a linha sem alterar o token ou o hash.

### Uma tentativa anterior deixou estado parcial

Não execute `kubeadm reset` como tentativa genérica de correção. Consulte primeiro os logs do kubelet e a saída de `kubeadm join`. O reset remove estado local do nó e deve ser usado apenas quando a decisão de recriar a associação estiver clara; veja os cuidados em [`comandos_kubernetes.md`](comandos_kubernetes.md).

Referências: [adicionar nós Linux com kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#join-nodes), [referência do comando `kubeadm join`](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/).
