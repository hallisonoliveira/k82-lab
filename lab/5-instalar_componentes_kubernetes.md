# Instalar kubeadm, kubelet e kubectl

Instale `kubeadm`, `kubelet` e `kubectl` em cada nó Kubernetes: `cp01`, `worker01` e `worker02`. Para manter as versões consistentes, use o mesmo repositório de versão secundária nos três nós. A VM `sre-tools` pode receber `kubectl` depois, quando for configurado o acesso administrativo ao cluster.

> Antes de prosseguir, conclua a configuração do `containerd` para Kubernetes, incluindo o plugin CRI habilitado e o driver de cgroups compatível com o kubelet. O guia [`3-instalar_containerd.md`](3-instalar_containerd.md) instala o daemon; essa configuração do runtime também é necessária.

## 5.1 Escolher a versão secundária

Escolha uma versão suportada do Kubernetes e consulte a página oficial [Instalar kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) correspondente a essa versão. O repositório `pkgs.k8s.io` é específico para cada versão secundária (`1.x`); não use o repositório legado `apt.kubernetes.io`.

Nos comandos abaixo, substitua `v1.XX` pela versão secundária escolhida, por exemplo `v1.XX` → `v1.34`. Use o mesmo valor nos três nós. Os pacotes instalados serão as versões disponibilizadas por esse repositório; `apt-mark hold` evita que uma atualização normal do sistema os atualize sem seguir o procedimento de upgrade do Kubernetes.

## 5.2 Adicionar o repositório em cada nó

Execute os comandos a seguir como usuário com `sudo` em `cp01`, `worker01` e `worker02`:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key |
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' |
  sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Substitua `v1.XX` antes de executar. A URL da chave pode conter a versão secundária escolhida; a chave de assinatura é compartilhada pelos repositórios Kubernetes.

## 5.3 Instalar e manter as versões alinhadas

Atualize o índice, instale os três componentes e marque-os para não serem atualizados automaticamente:

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Confirme as versões e o estado de hold em cada nó:

```bash
kubeadm version
kubelet --version
kubectl version --client
apt-mark showhold
```

`kubeadm` e `kubelet` devem usar versões compatíveis. Para este laboratório, mantenha a mesma versão secundária nos três nós e registre os números de versão instalados.

## 5.4 Habilitar o kubelet

Habilite o serviço para iniciar junto com o sistema:

```bash
sudo systemctl enable --now kubelet
systemctl is-enabled kubelet
```

Antes de `kubeadm init`/`kubeadm join`, é esperado que o `kubelet` reinicie ou apareça como não saudável, pois ainda não recebeu a configuração do cluster. Após inicializar o control plane e adicionar os workers, confira os registros com:

```bash
sudo systemctl status kubelet --no-pager
sudo journalctl -u kubelet -b --no-pager
```

## Critério para avançar

- Os três nós têm `kubeadm`, `kubelet` e `kubectl` instalados.
- As versões secundárias estão alinhadas e os pacotes aparecem em `apt-mark showhold`.
- O serviço `kubelet` está habilitado em todos os nós.
- O `containerd` está configurado para o CRI e cgroups usados pelo kubelet.

Referências: [instalar kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) e [política de version skew](https://kubernetes.io/docs/releases/version-skew-policy/).
