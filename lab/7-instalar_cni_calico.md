# Instalar a rede de Pods com Calico

Esta etapa instala Calico Open Source 3.33 no cluster kubeadm com Kubernetes 1.37. O Calico fornecerá a rede dos Pods e suporte a `NetworkPolicy`. A configuração deste laboratório usa `10.244.0.0/16`, o mesmo CIDR passado ao `kubeadm init`.

Execute os comandos em `cp01`, depois que a API estiver acessível e o kubeconfig administrativo funcionar. Calico é o CNI padrão deste laboratório.

Antes de instalar o Calico, confirme que o `kube-proxy` está presente e pronto:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods \
  -n kube-system -l k8s-app=kube-proxy -o wide
```

O Pod `kube-proxy` implementa o encaminhamento para endereços ClusterIP, incluindo `10.96.0.1` (Service da API Kubernetes). Se `kubeadm init` foi interrompido e o Pod não existir, retome a fase `kube-proxy` conforme [`comandos_kubernetes.md`](comandos_kubernetes.md) antes de prosseguir.

## 7.1 Instalar as definições de recursos e o operador

Para Kubernetes 1.36 ou posterior, a documentação do Calico 3.33 orienta instalar as CRDs `v1`:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/v3_projectcalico_org.yaml

sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f \
  https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
```

Espere o operador iniciar:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status \
  deployment/tigera-operator -n tigera-operator --timeout=5m
```

## 7.2 Configurar o CIDR do laboratório

O manifesto de exemplo do Calico usa outro CIDR. Baixe-o, altere o pool para `10.244.0.0/16` e confira a linha antes de aplicar:

```bash
curl -fsSLo /tmp/calico-custom-resources.yaml \
  https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/custom-resources.yaml

sed -i 's#cidr: 192.168.0.0/16#cidr: 10.244.0.0/16#' \
  /tmp/calico-custom-resources.yaml

grep -n 'cidr:' /tmp/calico-custom-resources.yaml
```

Confirme que a saída mostra `cidr: 10.244.0.0/16`, então aplique os recursos do operador. `apply` também pode ser repetido caso os recursos já existam:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f \
  /tmp/calico-custom-resources.yaml
```

O manifesto oficial também habilita o Calico API Server, o agregador de fluxos Goldmane e a interface Whisker. Eles dão visibilidade de fluxos de rede; não substituem a coleta de logs, métricas e traces com Fluent Bit e OpenTelemetry.

## 7.3 Acompanhar a instalação

Veja a disponibilidade dos componentes e o estado do cluster:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get tigerastatus
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide
```

Espere os componentes Calico ficarem disponíveis e os nós Linux aparecerem como `Ready`. CoreDNS deve iniciar quando a rede dos Pods estiver operacional. Se houver falhas:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n calico-system -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf describe tigerastatus
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -A \
  --sort-by=.metadata.creationTimestamp
```

### Critério para avançar

- `tigerastatus` mostra os componentes Calico disponíveis.
- `cp01` aparece como `Ready`.
- CoreDNS está `Running`.
- O pool de endereços do Calico está configurado como `10.244.0.0/16`.

Referências: [guia oficial de instalação do Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart) e [requisitos e versões Kubernetes testadas](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements).

## Troubleshooting

Durante a instalação inicial, os eventos podem mostrar avisos transitórios enquanto o nó ainda está `NotReady` e o CNI está sendo configurado. Exemplos observados neste laboratório:

- `FailedScheduling` por taint não tolerado: os Pods aguardam o nó ficar pronto ou o taint de inicialização ser removido.
- `NetworkNotReady` com `cni plugin not initialized`: o runtime ainda não encontrou a configuração CNI do Calico.
- Falhas temporárias de readiness/startup probes em `calico-node`, Typha, webhooks ou Goldmane: os componentes ainda estão subindo ou aguardando conectividade.

Esses avisos, quando antigos, não indicam por si só uma falha atual. Confirme o estado presente dos componentes e do nó:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get tigerastatus
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n calico-system -o wide
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -o wide
```

Considere a rede operacional quando os status do Tigera mostrarem `Available=True`, `Degraded=False` e `Progressing=False`, os Pods do Calico estiverem prontos e o nó estiver `Ready`. Se algum componente continuar falhando, investigue os eventos e logs atuais:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -A \
  --sort-by=.metadata.creationTimestamp
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf logs \
  -n calico-system <pod> --all-containers=true --tail=100
```
