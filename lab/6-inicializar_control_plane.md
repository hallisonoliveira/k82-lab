# Inicializar o control plane

Esta etapa inicializa o primeiro e único control plane do laboratório com `kubeadm`. Execute-a apenas na VM `cp01` (`192.168.50.10`), depois de concluir a instalação e configuração do runtime, desativar swap e instalar os componentes Kubernetes nos três nós.

## 6.1 Conferir os pré-requisitos

Antes de inicializar, confirme que:

- `containerd` está ativo e configurado para CRI, com `SystemdCgroup = true` no `runc` runtime usado pelo containerd.
- `kubeadm`, `kubelet` e `kubectl` estão instalados e em versões compatíveis nos três nós.
- Swap está desativado nos nós Kubernetes.
- Os nós resolvem os nomes uns dos outros e usam IPs estáveis.
- O CIDR escolhido para Pods não se sobrepõe à rede das VMs, rede doméstica, VPN ou à futura rede de Services.

Confira em `cp01`:

```bash
sudo systemctl is-active containerd
sudo ctr plugins ls | grep -i cri
swapon --show
ip -4 addr
```

O plugin CRI deve aparecer como carregado e `ok`. Veja a [documentação de runtimes de contêiner](https://kubernetes.io/docs/setup/production-environment/container-runtimes/) para a configuração de cgroups.

## 6.2 Preparar o endpoint da API

A proposta prevê adicionar control planes no futuro. Para facilitar essa expansão, o cluster será criado usando um endpoint DNS estável: `k8s-api.lab`. No início, esse nome aponta para o IP de `cp01`; quando houver um balanceador, o nome poderá passar a apontar para ele.

Adicione esta linha ao arquivo `/etc/hosts` **em cada uma das quatro VMs**:

```text
192.168.50.10 k8s-api.lab
```

Valide a resolução em `cp01`, `worker01`, `worker02` e `sre-tools`:

```bash
getent hosts k8s-api.lab
```

O resultado deve apontar para `192.168.50.10`. Se você usa outros IPs, adapte o endereço. Preserve o nome `k8s-api.lab` nas configurações futuras; ao implantar o balanceador, altere para que esse nome resolva para o endereço dele.

## 6.3 Escolher a rede de Pods

Este guia usa `10.244.0.0/16` como CIDR de Pods, desde que esteja livre na rede local e VPN. A rede do plugin CNI instalado na próxima etapa deverá usar exatamente o mesmo CIDR. O CIDR padrão de alguns plugins pode ser diferente; configure o plugin para corresponder ao valor usado aqui.

Não passe `--service-cidr` neste primeiro laboratório: o Kubernetes usará o padrão `10.96.0.0/12`. Confirme que esse intervalo também não conflita com redes acessíveis a partir das VMs.

## 6.4 Validar memória e encaminhamento IP

Antes de executar `kubeadm init`, confira os recursos e o encaminhamento IPv4 em `cp01`:

```bash
free -h
grep MemTotal /proc/meminfo
sysctl net.ipv4.ip_forward
```

O `kubeadm` exige pelo menos **1700 MB de RAM** para o control plane. Se `MemTotal` estiver abaixo desse valor — por exemplo, `1577 MB` — desligue a VM e aumente sua memória no hypervisor para pelo menos **2 GB**. Se o hypervisor ou o sistema reservar parte dessa memória e o valor continuar abaixo do mínimo, aumente a alocação um pouco além de 2 GB. Inicie novamente a VM e confirme com `free -h` antes de prosseguir. Não use `--ignore-preflight-errors=Mem`: o control plane e o etcd podem falhar ou ficar instáveis por falta de memória.

O encaminhamento IPv4 precisa estar habilitado para a rede de Pods. Aplique a configuração persistente e carregue-a agora:

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
sudo sysctl --system
sysctl net.ipv4.ip_forward
```

O último comando deve mostrar `net.ipv4.ip_forward = 1`. Se não mostrar, confira a saída de `sudo sysctl --system` e resolva qualquer erro antes de iniciar o cluster.

## 6.5 Executar `kubeadm init`

Na VM `cp01`, inicialize o cluster. O endereço de anúncio é o IP estável do control plane; o endpoint compartilhado é o nome DNS preparado acima.

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.50.10 \
  --control-plane-endpoint=k8s-api.lab:6443 \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

Se sua rede, versão ou configuração do runtime for diferente, ajuste os valores antes de executar. O comando baixa imagens do Kubernetes e inicia os componentes do control plane; pode levar alguns minutos.

Guarde o resultado. Em particular, copie o comando `kubeadm join` exibido ao final para um local seguro: os workers precisarão dele na etapa de entrada no cluster. O token é uma credencial temporária; não o publique nem o inclua em arquivos versionados.

Se `kubeadm init` terminar com erro antes de exibir o comando `kubeadm join`, mas o API Server já estiver funcionando, gere um novo token e o comando completo em `cp01` com:

```bash
sudo kubeadm token create --print-join-command
```

Esse comando cria um token temporário e imprime a linha `kubeadm join` correspondente. Guarde-a em local seguro para usar na etapa de entrada dos workers.

## 6.6 Configurar `kubectl` em `cp01`

Como o usuário Linux que administrará o cluster em `cp01`, configure o kubeconfig:

```bash
mkdir -p "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```

O arquivo `admin.conf` concede privilégios administrativos ao cluster. Mantenha-o privado e não o envie para repositórios ou compartilhe. A cópia para `sre-tools` será documentada na etapa de configuração de acesso administrativo.

Confira o estado inicial:

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

Antes de instalar o CNI, é esperado que `cp01` apareça como `NotReady`, que CoreDNS ainda não esteja `Running` e que o kubelet reporte `NetworkPluginNotReady`. Isso, por si só, não significa que `kubeadm init` falhou: a rede de Pods será configurada na próxima etapa, [instalação do Calico](7-instalar_cni_calico.md). Depois de instalar o CNI, esses estados devem se normalizar.

## Critério para avançar

- `kubeadm init` terminou com sucesso em `cp01`.
- `kubectl` consegue consultar o API Server a partir de `cp01`.
- O endpoint `k8s-api.lab:6443` está registrado no cluster e resolve para o IP atual de `cp01`.
- O comando de `kubeadm join` foi guardado em local seguro para a etapa de entrada dos workers.

Referências oficiais: [criar um cluster com kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/) e [runtime de contêineres](https://kubernetes.io/docs/setup/production-environment/container-runtimes/).
