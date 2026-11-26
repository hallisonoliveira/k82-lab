# Referência de comandos Kubernetes

Coleção transversal de comandos usados no laboratório e em rotinas comuns de SRE. Execute os comandos `kubectl` em uma máquina com kubeconfig configurado e acesso ao cluster. Nos exemplos do control plane, use `sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf` se o usuário ainda não tiver configurado `~/.kube/config`.

Substitua valores entre `<colchetes>`. Não cole tokens, kubeconfigs, chaves ou saídas com credenciais em repositórios, tickets públicos ou conversas compartilhadas.

## `kubeadm`: ciclo de vida e bootstrap

`kubeadm` prepara os nós e inicializa ou associa máquinas ao cluster. Não é a ferramenta usada para consultar Pods ou operar aplicações no dia a dia.

### Inicializar o control plane

Execute uma vez em `cp01`, depois de validar runtime, memória, swap, rede e resolução do endpoint:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.50.10 \
  --control-plane-endpoint=k8s-api.lab:6443 \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

`--pod-network-cidr` define o intervalo de IP dos Pods. Ele precisa corresponder ao configurado no CNI (Calico nesta configuração). Uma falha do comando não significa que se deva repeti-lo imediatamente: primeiro confira a API, os manifests e os logs; um `kubeadm init` repetido sobre um control plane já criado falha nos preflight checks porque portas, manifests e dados do etcd estão em uso.

### Retomar a instalação do kube-proxy

`kubeadm init` instala o addon `kube-proxy`. Se a inicialização foi interrompida e o API Server está acessível, mas não existe Pod `kube-proxy` em `kube-system`, execute somente a fase desse addon em `cp01`:

```bash
sudo kubeadm init phase addon kube-proxy \
  --kubernetes-version=v1.37.2 \
  --apiserver-advertise-address=192.168.50.10 \
  --control-plane-endpoint=k8s-api.lab:6443 \
  --pod-network-cidr=10.244.0.0/16 \
  --kubeconfig=/etc/kubernetes/admin.conf
```

Depois confirme que o DaemonSet e o Pod do kube-proxy estão prontos:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status \
  daemonset/kube-proxy -n kube-system --timeout=5m
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l k8s-app=kube-proxy -o wide
```

Use a mesma versão do control plane no argumento `--kubernetes-version`. `kubeadm init phase` retoma uma etapa atômica do bootstrap sem repetir toda a inicialização.

### Completar configuração e bootstrap após um `kubeadm init` interrompido

Se o control plane já está saudável, mas faltam os ConfigMaps `kubeadm-config`, `kubelet-config` e `cluster-info`, não repita `kubeadm init`. Recrie um arquivo de configuração com os mesmos parâmetros usados na inicialização:

```bash
sudo tee /tmp/kubeadm-recovery.yaml >/dev/null <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.50.10
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  name: k8s-cp01
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: kubernetes
kubernetesVersion: v1.37.2
controlPlaneEndpoint: k8s-api.lab:6443
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
```

Envie as configurações ao cluster e conclua a configuração de bootstrap tokens:

```bash
sudo kubeadm init phase upload-config all \
  --config=/tmp/kubeadm-recovery.yaml \
  --kubeconfig=/etc/kubernetes/admin.conf

# Garanta explicitamente o ConfigMap versionado usado pelo kubelet.
sudo kubeadm init phase upload-config kubelet \
  --config=/tmp/kubeadm-recovery.yaml \
  --kubeconfig=/etc/kubernetes/admin.conf

sudo kubeadm init phase bootstrap-token \
  --config=/tmp/kubeadm-recovery.yaml \
  --kubeconfig=/etc/kubernetes/admin.conf \
  --skip-token-print
```

Verifique se os ConfigMaps foram criados antes de adicionar workers:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get configmap \
  kubeadm-config kubelet-config -n kube-system
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get configmap \
  cluster-info -n kube-public
```

O arquivo de recuperação deve refletir exatamente a versão, o endpoint e as redes já usados no cluster. `bootstrap-token` cria um token temporário; não compartilhe saídas que contenham tokens.

### Instalar CoreDNS após a rede dos Pods

Se `kubeadm init` foi interrompido antes da fase de addons, instale CoreDNS depois que o CNI estiver funcionando:

```bash
sudo kubeadm init phase addon coredns \
  --kubernetes-version=v1.37.2 \
  --kubeconfig=/etc/kubernetes/admin.conf
```

Confira o Deployment e os Pods. CoreDNS precisa do CNI para iniciar:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status \
  deployment/coredns -n kube-system --timeout=5m
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l k8s-app=kube-dns -o wide
```

### Marcar o nó como control plane

Se `kubectl get nodes` mostrar `<none>` em `ROLES` para `cp01` porque a inicialização foi interrompida antes dessa fase, aplique o rótulo e a taint padrão:

```bash
sudo kubeadm init phase mark-control-plane --node-name k8s-cp01
```

Confira o resultado com `kubectl get nodes -o wide`. A taint padrão impede o agendamento de workloads comuns no control plane.

### Gerar o comando para adicionar workers

Se o `init` concluiu, copie o `kubeadm join` mostrado no final. Se esse comando não foi exibido, mas a API já está acessível, gere outro em `cp01`:

```bash
sudo kubeadm token create --print-join-command
```

O resultado inclui um token temporário. Trate a linha inteira como credencial: não a versione nem a compartilhe. Execute o comando `kubeadm join` em cada worker, substituindo ou mantendo exatamente os parâmetros gerados.

### Conferir tokens de bootstrap

```bash
sudo kubeadm token list
```

Lista tokens ativos e sua validade. Para gerar um novo token e imprimir a linha de associação, use `kubeadm token create --print-join-command`.

### Conferir expiração de certificados

```bash
sudo kubeadm certs check-expiration
```

Consulta as datas de expiração dos certificados gerenciados pelo kubeadm. Não renove certificados como ação de rotina sem entender o procedimento de manutenção e reinício dos componentes.

### Restaurar acesso do API Server ao kubelet

Em clusters kubeadm 1.36 ou posterior, o API Server usa a identidade `kube-apiserver-kubelet-client` para acessar a API do kubelet. A fase `bootstrap-token` do `kubeadm init` cria o vínculo RBAC necessário. Se a inicialização foi interrompida antes dessa fase, comandos como `kubectl logs`, `kubectl exec` e port-forward podem falhar com `Forbidden` em `nodes/proxy`.

Use um kubeconfig administrativo para aplicar o vínculo esperado pelo kubeadm:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:apiserver-kubelet-client
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kubelet-api-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: kube-apiserver-kubelet-client
EOF
```

Esse vínculo concede à identidade do API Server o acesso ao kubelet necessário para operações como logs e exec. Depois de aplicá-lo, tente novamente os comandos que falharam. Não conceda `system:kubelet-api-admin` a usuários humanos ou contas de aplicação.

### Resetar um nó

```bash
sudo kubeadm reset
```

Remove estado local criado pelo kubeadm e pode interromper a participação do nó no cluster. É uma ação de recuperação/recriação, não um passo para corrigir erros de CNI ou repetir `kubeadm init`. Confirme que o nó pode ser removido e consulte o guia da etapa antes de executar.

## `kubectl`: consultas do dia a dia

`kubectl` envia consultas e alterações para a API do cluster. O kubeconfig define a identidade e o cluster de destino.

### Criar o alias `k`

Em `sre-tools`, para o usuário que executa `kubectl`, adicione o alias ao `~/.bashrc`:

```bash
echo "alias k='kubectl'" >> ~/.bashrc
source ~/.bashrc
```

`source` ativa o alias na sessão Bash atual; novas sessões interativas também carregarão o arquivo. Valide com:

```bash
k get nodes
```

O alias é uma conveniência do shell e não altera a configuração do cluster. Em scripts, prefira chamar `kubectl` explicitamente para não depender de aliases interativos.

### Contexto e identidade

```bash
kubectl config get-contexts
kubectl config current-context
kubectl config use-context <contexto>
kubectl auth whoami
```

Confira o contexto antes de fazer alterações, especialmente quando administra mais de um cluster.

### Ver estado de nós e workloads

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get deployments -A
kubectl get services -A
kubectl get namespaces
```

`-A` lista todos os namespaces; sem essa opção, `kubectl` consulta apenas o namespace atual. `-o wide` acrescenta campos úteis como IP e nó.

### Inspecionar um recurso e seus eventos

```bash
kubectl describe pod <pod> -n <namespace>
kubectl describe node <node>
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

Use `describe` para condições, agendamento, probes e eventos associados ao objeto. Eventos ajudam a encontrar erros recentes, mas expiram; para histórico mais longo, centralize logs e eventos.

### Consultar logs de contêineres

```bash
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> -c <container>
kubectl logs <pod> -n <namespace> --previous
kubectl logs -f <pod> -n <namespace>
```

`--previous` consulta a instância anterior do contêiner, útil após um reinício. `-f` acompanha novas linhas em tempo real. Para vários Pods selecionados por label:

```bash
kubectl logs -n <namespace> -l app=<label> --all-containers=true --since=1h
```

### Entrar em um contêiner para diagnóstico

```bash
kubectl exec -it <pod> -n <namespace> -- sh
kubectl exec -it <pod> -n <namespace> -c <container> -- sh
```

Use para diagnóstico pontual. Prefira imagens de troubleshooting aprovadas quando a imagem da aplicação não contém shell ou ferramentas de rede. Evite alterar manualmente o contêiner: mudanças feitas fora dos manifests e controladores não são duráveis.

### Uso de CPU e memória

```bash
kubectl top nodes
kubectl top pods -A
kubectl top pods -n <namespace> --containers
```

Requer Metrics Server ou outra fonte de métricas compatível. Esses valores ajudam em triagem rápida; para tendências, alertas e SLOs, use uma plataforma de métricas.

## `kubectl`: operação de aplicações

### Instalar/atualizar uma aplicação com Helm

O Helm não é parte do `kubectl`, mas é usado no laboratório para instalar charts como `podinfo`. Execute em `sre-tools` com contexto e kubeconfig corretos:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm upgrade --install podinfo podinfo/podinfo \
  --namespace lab-sre --create-namespace \
  --values podinfo-values.yaml --wait --timeout 5m
helm status podinfo -n lab-sre
helm history podinfo -n lab-sre
```

`upgrade --install` é repetível para a mesma release; revise os valores e o namespace antes de aplicar. `helm uninstall` remove os recursos gerenciados pela release e não deve ser usado como forma de reiniciar Pods.

### Acompanhar e desfazer um rollout

```bash
kubectl rollout status deployment/<deployment> -n <namespace>
kubectl rollout history deployment/<deployment> -n <namespace>
kubectl rollout undo deployment/<deployment> -n <namespace>
```

Confira o status e a revisão antes do rollback. O rollback reverte o template do Deployment para uma revisão anterior, mas não desfaz necessariamente alterações em banco de dados ou outros recursos externos.

### Escalar réplicas

```bash
kubectl scale deployment/<deployment> --replicas=<quantidade> -n <namespace>
```

Se um HPA controla o Deployment, alterar manualmente `replicas` pode conflitar com o autoscaler. Consulte primeiro:

```bash
kubectl get hpa -A
kubectl describe hpa <hpa> -n <namespace>
```

### Verificar disponibilidade e probes

```bash
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod> -n <namespace>
kubectl get endpointslices -n <namespace>
```

Use os endpointslices para confirmar quais Pods prontos recebem tráfego por um Service.

## Manutenção de nós

### Impedir novos agendamentos e drenar workloads

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets
```

`cordon` marca o nó como não agendável. `drain` remove Pods que podem ser recriados em outros nós e pode sofrer bloqueios de PodDisruptionBudget. Planeje capacidade, disponibilidade e armazenamento antes de drenar.

Após a manutenção:

```bash
kubectl uncordon <node>
kubectl get nodes -o wide
```

`uncordon` permite novamente o agendamento no nó. Confirme que o nó está saudável antes de reabri-lo.

### Excluir um Pod para testar recuperação

```bash
kubectl delete pod <pod> -n <namespace>
```

Use apenas em exercícios ou incidentes em que essa ação seja apropriada. Um controlador como Deployment normalmente cria outro Pod; um Pod sem controlador pode não voltar.

Para acompanhar Pods em tempo real e verificar os endpoints do Service depois da substituição:

```bash
kubectl get pods -n <namespace> -o wide -w
kubectl get endpointslices -n <namespace> -w
```

Interrompa a observação com `Ctrl+C`. A exclusão provoca interrupção potencial e deve ser feita apenas no workload de laboratório escolhido.

## Saída estruturada e filtros

```bash
kubectl get pods -n <namespace> -o yaml
kubectl get pod <pod> -n <namespace> -o json
kubectl get pods -n <namespace> -l app=<label>
kubectl get pods -n <namespace> --field-selector=status.phase!=Running
```

Saídas YAML/JSON são úteis para automação e inspeção de campos. Revise-as antes de compartilhar: objetos podem conter nomes internos, endereços e dados de configuração.

## Referências oficiais

- [`kubectl` — referência de comandos](https://kubernetes.io/docs/reference/kubectl/)
- [`kubeadm init`](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/)
- [Criar um cluster com kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Operações de manutenção e drain](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)
