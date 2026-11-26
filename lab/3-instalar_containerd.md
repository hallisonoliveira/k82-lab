# Instalar containerd

Instale o `containerd` em cada nó que fará parte do cluster Kubernetes: `cp01`, `worker01` e `worker02`. A VM `sre-tools` não precisa do runtime enquanto for usada apenas para administrar o cluster.

Este procedimento baixa o arquivo compactado oficial das versões do containerd, copia-o para cada VM, instala os binários em `/usr/local` e registra o serviço `containerd` no systemd.

## 3.1 Baixar a versão do containerd

Abra a página oficial de [releases do containerd](https://github.com/containerd/containerd/releases) e escolha uma versão estável compatível com a versão de Kubernetes que será instalada. Baixe o arquivo para Linux `amd64`, cujo nome segue este padrão:

```text
containerd-[versao]-linux-amd64.tar.gz
```

Por exemplo, substitua `[versao]` pela versão escolhida, sem o `v` inicial se o nome do arquivo publicado não o incluir. Guarde o número da versão: ele será usado nos comandos abaixo. Este guia presume VMs Ubuntu Server em arquitetura `amd64`; confirme a arquitetura com `uname -m` (esperado: `x86_64`).

Baixe também o arquivo de unidade systemd oficial do repositório do containerd: [`containerd.service`](https://raw.githubusercontent.com/containerd/containerd/main/containerd.service). Salve-o com o nome exato `containerd.service` — a extensão é `.service`.

## 3.2 Copiar os arquivos para as VMs

No PowerShell do Windows, a partir da pasta onde os dois arquivos foram salvos, copie-os para o diretório pessoal do usuário correspondente em cada VM. Troque `VERSAO` pela versão selecionada e ajuste nomes de usuário, IPs ou caminhos locais se forem diferentes no seu ambiente.

```powershell
$versao = 'VERSAO'
$arquivo = "containerd-$versao-linux-amd64.tar.gz"
$nos = @(
    @{ Usuario = 'cp01'; Endereco = '192.168.50.10' }
    @{ Usuario = 'worker01'; Endereco = '192.168.50.11' }
    @{ Usuario = 'worker02'; Endereco = '192.168.50.12' }
)

foreach ($no in $nos) {
    $destino = "$($no.Usuario)@$($no.Endereco):~/"
    scp $arquivo $destino
    scp .\containerd.service "$($no.Usuario)@$($no.Endereco):~/containerd.service"
}
```

Se a sintaxe de interpolação do PowerShell não funcionar na sua versão, faça a cópia nó a nó, por exemplo:

```powershell
scp .\containerd-VERSAO-linux-amd64.tar.gz cp01@192.168.50.10:~/
scp .\containerd.service cp01@192.168.50.10:~/
```

Repita para `worker01` (`192.168.50.11`) e `worker02` (`192.168.50.12`). O `scp` usa as mesmas credenciais/acesso SSH preparados na etapa anterior.

## 3.3 Instalar o `runc` e os binários do containerd

O containerd precisa de um runtime OCI para criar contêineres. Instale o `runc` pelo repositório do Ubuntu em cada nó Kubernetes:

```bash
sudo apt-get update
sudo apt-get install -y runc
command -v runc
runc --version
```

`command -v runc` deve mostrar o caminho do executável e `runc --version` deve imprimir sua versão. Se o pacote não estiver disponível na versão do Ubuntu escolhida, consulte as instruções oficiais de instalação do containerd para instalar uma versão compatível do `runc`.

Depois conecte-se por SSH a cada nó e instale os binários do containerd. No exemplo, substitua `VERSAO` pela versão efetivamente baixada. O arquivo tarball deve estar no diretório atual (neste caso, `~`).

```bash
cd ~
sudo tar Cxzvf /usr/local containerd-VERSAO-linux-amd64.tar.gz
```

O argumento `C` indica ao `tar` que use `/usr/local` como diretório de destino; `x`, `z`, `v` e `f` extraem, leem gzip, mostram os arquivos e indicam o nome do arquivo, respectivamente. A extração instala os binários sob `/usr/local/bin`.

Confirme que o binário foi instalado:

```bash
/usr/local/bin/containerd --version
```

## 3.4 Instalar a unidade systemd

Ainda em cada VM, crie o diretório de unidades locais caso ele não exista e copie o arquivo baixado para lá:

```bash
sudo mkdir -p /usr/local/lib/systemd/system
sudo cp ~/containerd.service /usr/local/lib/systemd/system/containerd.service
```

O nome correto do arquivo é `containerd.service` (não `containerd.sevice`). Verifique se ele aponta para o binário instalado em `/usr/local/bin/containerd`:

```bash
grep '^ExecStart=' /usr/local/lib/systemd/system/containerd.service
```

## 3.5 Carregar e iniciar o serviço

Execute os comandos em cada nó:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
```

Confira se o serviço iniciou e ficará habilitado após reinicializações:

```bash
systemctl is-active containerd
systemctl is-enabled containerd
sudo systemctl status containerd --no-pager
```

Os dois primeiros comandos devem retornar `active` e `enabled`. Se houver falha, consulte os registros:

```bash
sudo journalctl -u containerd -b --no-pager
```

### Critério para avançar

- O binário `containerd` está instalado nos três nós Kubernetes.
- O executável `runc` está instalado e pode ser encontrado no `PATH` dos três nós.
- O serviço está `active` e `enabled` em `cp01`, `worker01` e `worker02`.
- A versão instalada corresponde à escolhida na página oficial de releases.

> Esta etapa instala e inicia o daemon. A configuração do runtime para o Kubernetes — incluindo `runc`, o plugin CRI e o driver de cgroups compatível com o kubelet — também precisa estar pronta antes da instalação do kubelet e da inicialização do cluster.
