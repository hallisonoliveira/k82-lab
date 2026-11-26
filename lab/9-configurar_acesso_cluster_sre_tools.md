# Configurar o acesso ao cluster na VM `sre-tools`

Esta etapa prepara a VM `sre-tools` para administrar o cluster com `kubectl`. O acesso será feito pela API em `k8s-api.lab:6443`, usando um kubeconfig próprio para um usuário humano com permissões administrativas no laboratório. Execute os comandos de instalação e configuração em `sre-tools`; use `cp01` apenas para criar a identidade e a autorização.

Pré-requisitos: etapas [6 — inicializar o control plane](6-inicializar_control_plane.md), [7 — instalar o Calico](7-instalar_cni_calico.md) e [8 — adicionar os workers](8-adicionar_workers.md) concluídas. O cluster deve estar saudável e `k8s-api.lab` deve resolver para o endereço atual do control plane a partir de `sre-tools`.

## 9.1 Validar a conectividade

Em `sre-tools`, confirme a resolução do endpoint e o acesso TCP à API:

```bash
getent hosts k8s-api.lab
nc -vz k8s-api.lab 6443
```

O nome deve resolver para o IP atual de `cp01` (neste laboratório, `192.168.50.10`) e a porta 6443 deve aceitar conexão. Se falhar, revise a entrada de `/etc/hosts`, as rotas e o firewall conforme [2 — configurar rede e conectividade](2-configurar_rede_e_conectividade.md). Não continue copiando credenciais até a conectividade funcionar.

## 9.2 Instalar `kubectl`

Instale em `sre-tools` uma versão do `kubectl` dentro de uma versão menor de diferença do cluster. Neste laboratório, o cluster é `v1.37.2` e o repositório configurado é o canal `v1.37`. A versão do pacote APT não leva o prefixo `v`. Para a instalação inicial, deixe o APT selecionar a versão disponível nesse canal; o `kubectl` pode estar até uma versão menor acima ou abaixo da API server.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
KUBERNETES_MINOR=1.37
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/Release.key" \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_MINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
kubectl version --client
```

Se o APT ainda não encontrar uma versão, confira `apt-cache policy kubectl` e confirme que `sudo apt-get update` terminou sem erro e que o repositório da série desejada está em `/etc/apt/sources.list.d/kubernetes.list`. O exemplo `1.37.x-*` da documentação de upgrade é um padrão explicativo: substitua `x` pelo patch publicado, ou instale sem fixar versão como neste guia. Consulte a [documentação oficial de instalação do kubectl para Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) e a [orientação oficial sobre versões de pacotes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/).

## 9.3 Criar uma identidade administrativa do laboratório

`/etc/kubernetes/admin.conf` é uma credencial de superusuário do cluster. Não a copie para `sre-tools`: em vez disso, crie em `cp01` uma identidade de usuário e um certificado cliente com validade limitada. O exemplo usa `lab-admin` com papel `cluster-admin`, adequado para este laboratório individual. Em uma equipe ou ambiente real, conceda apenas as permissões necessárias a cada pessoa.

Em `cp01`, execute como usuário que possui `/etc/kubernetes/admin.conf`:

```bash
umask 077
mkdir -p "$HOME/lab-credentials"
cd "$HOME/lab-credentials"
openssl genrsa -out lab-admin.key 3072
openssl req -new -key lab-admin.key -out lab-admin.csr \
  -subj "/CN=lab-admin/O=lab-sre"
CSR_BASE64=$(base64 -w0 lab-admin.csr)
cat <<EOF | sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: lab-admin
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 2592000
  usages:
  - client auth
EOF
```

Aprove a CSR e obtenha o certificado emitido:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf certificate approve lab-admin
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get csr lab-admin
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get csr lab-admin \
  -o jsonpath='{.status.certificate}' | base64 -d > lab-admin.crt
```

Confira que o arquivo `lab-admin.crt` não está vazio antes de continuar. A CSR aprovada dá ao portador da chave privada a identidade `lab-admin` no grupo `lab-sre`; autorize-a no cluster:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf create clusterrolebinding lab-sre-admin \
  --clusterrole=cluster-admin \
  --user=lab-admin \
  --group=lab-sre
```

O papel `cluster-admin` permite alterações em todos os namespaces e recursos. Não use essa identidade em aplicações ou automações compartilhadas.

## 9.4 Transferir credenciais e montar o kubeconfig

Transfira os três arquivos `lab-admin.crt`, `lab-admin.key` e `/etc/kubernetes/pki/ca.crt` para `sre-tools` por SSH/SCP. Faça a transferência diretamente para o diretório privado do usuário que executará `kubectl`; não os coloque no repositório.

Exemplo iniciado em `cp01`, adaptando `usuario` e o IP de `sre-tools`:

```bash
scp lab-admin.crt lab-admin.key usuario@192.168.50.20:/home/usuario/
sudo cp /etc/kubernetes/pki/ca.crt /tmp/k8s-lab-ca.crt
sudo chown "$USER:$USER" /tmp/k8s-lab-ca.crt
scp /tmp/k8s-lab-ca.crt usuario@192.168.50.20:/home/usuario/
rm -f /tmp/k8s-lab-ca.crt
```

No `sre-tools`, proteja os arquivos e crie um kubeconfig independente:

```bash
mkdir -p "$HOME/.kube" "$HOME/.kube/credentials"
chmod 700 "$HOME/.kube" "$HOME/.kube/credentials"
mv "$HOME/lab-admin.crt" "$HOME/lab-admin.key" "$HOME/k8s-lab-ca.crt" "$HOME/.kube/credentials/"
chmod 600 "$HOME/.kube/credentials/lab-admin.key"
chmod 644 "$HOME/.kube/credentials/lab-admin.crt" "$HOME/.kube/credentials/k8s-lab-ca.crt"

kubectl config set-cluster k8s-lab \
  --server=https://k8s-api.lab:6443 \
  --certificate-authority="$HOME/.kube/credentials/k8s-lab-ca.crt" \
  --embed-certs=true
kubectl config set-credentials lab-admin \
  --client-certificate="$HOME/.kube/credentials/lab-admin.crt" \
  --client-key="$HOME/.kube/credentials/lab-admin.key" \
  --embed-certs=true
kubectl config set-context k8s-lab-admin \
  --cluster=k8s-lab --user=lab-admin --namespace=default
kubectl config use-context k8s-lab-admin
chmod 600 "$HOME/.kube/config"
```

O kubeconfig contém a chave privada embutida. Mantenha-o legível somente pelo usuário dono e fora de backups ou compartilhamentos sem proteção.

## 9.5 Validar o acesso

Ainda em `sre-tools`, verifique o contexto, a identidade e o estado do cluster:

```bash
kubectl config current-context
kubectl auth whoami
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

O contexto deve ser `k8s-lab-admin`, a identidade deve ser `lab-admin` e os nós devem aparecer `Ready`. O kubeconfig e o endpoint também podem ser inspecionados sem imprimir certificados:

```bash
kubectl config view --minify
kubectl cluster-info
```

Não publique a saída completa de `kubectl config view --raw`: ela revela credenciais.

### Critério para avançar

- `kubectl` está instalado em `sre-tools` numa versão menor compatível com o cluster.
- `k8s-api.lab:6443` é acessível e validado com a CA do cluster.
- O usuário `lab-admin` autentica e consegue consultar nós e Pods.
- Nenhuma cópia de `admin.conf`, chave privada ou kubeconfig foi adicionada ao repositório.

## Troubleshooting

### `Unable to connect to the server` ou timeout

Confirme `getent hosts k8s-api.lab`, `nc -vz k8s-api.lab 6443` e as rotas. Verifique se a API está ativa em `cp01` com `sudo systemctl status kubelet` e se o endereço no kubeconfig corresponde ao endpoint usado na inicialização.

### Erro de certificado ou autoridade desconhecida

Confirme que `k8s-lab-ca.crt` veio de `/etc/kubernetes/pki/ca.crt` no control plane, que o relógio das VMs está sincronizado e que o servidor do contexto é `https://k8s-api.lab:6443`. Não contorne o erro desativando a verificação TLS.

### `Forbidden`

Confirme a identidade com `kubectl auth whoami`. Em `cp01`, confira se a CSR foi aprovada e se o ClusterRoleBinding `lab-sre-admin` associa `lab-admin` ao papel esperado. Evite resolver o erro copiando `admin.conf` para `sre-tools`.

### Revogar o acesso administrativo do laboratório

Em `cp01`, remova a autorização e a CSR:

```bash
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf delete clusterrolebinding lab-sre-admin
sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf delete csr lab-admin
```

Apague também a chave privada, o certificado e o kubeconfig dos locais de transferência e de `sre-tools`. Para voltar a conceder acesso, gere uma nova chave e uma nova CSR; não reutilize uma chave que possa ter sido exposta.

Referências: [instalar kubectl no Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/), [CertificateSigningRequest](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/), [autenticação por certificados](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#x509-client-certs) e [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/).
