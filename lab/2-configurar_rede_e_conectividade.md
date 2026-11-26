# Configurar rede e conectividade

Nesta etapa, conecte o Windows host e as quatro VMs em uma rede de laboratório. As VMs precisam alcançar umas às outras, o Windows precisa conseguir abrir sessões SSH e as VMs precisam de acesso à internet para baixar pacotes e imagens.

Este guia segue a topologia Hyper-V documentada em [`rede-hyper-v.md`](rede-hyper-v.md). Ela usa um switch interno e NAT no Windows. Se estiver usando VirtualBox, configure uma interface NAT para saída à internet e uma interface host-only para o tráfego entre host e VMs; nesse caso, adapte os endereços e valide qual interface será usada pelo Kubernetes.

## 2.1 Topologia e endereços

O exemplo abaixo reserva `192.168.50.1` para o Windows/gateway e endereços estáticos para as VMs:

| Máquina | Nome de host | IPv4 | Prefixo | Gateway |
| --- | --- | --- | --- | --- |
| Windows host | — | `192.168.50.1` | `/24` | — |
| Control plane | `cp01` | `192.168.50.10` | `/24` | `192.168.50.1` |
| Worker 1 | `worker01` | `192.168.50.11` | `/24` | `192.168.50.1` |
| Worker 2 | `worker02` | `192.168.50.12` | `/24` | `192.168.50.1` |
| Ferramentas | `sre-tools` | `192.168.50.20` | `/24` | `192.168.50.1` |

Antes de usar esse bloco, confirme que `192.168.50.0/24` não se sobrepõe à rede doméstica, VPN ou outra rede do host. Se houver conflito, escolha outro prefixo privado e atualize os IPs no switch/NAT, nas VMs e no [`conectar-lab.ps1`](../conectar-lab.ps1).

> **Consistência dos nomes:** o primeiro guia identifica a VM como `k8s-cp01`, enquanto o script de conexão e este mapa usam o hostname `cp01`. O nome da VM no hypervisor pode continuar `k8s-cp01`; configure o hostname Linux como `cp01` para coincidir com o script. Os demais hostnames são `worker01`, `worker02` e `sre-tools`.

## 2.2 Criar a rede no Hyper-V

No Windows Pro ou Enterprise, siga [`rede-hyper-v.md`](rede-hyper-v.md) para criar o switch interno `K8sLab`, atribuir `192.168.50.1/24` ao adaptador `vEthernet (K8sLab)` e criar o NAT `K8sLabNAT`. Conecte as quatro VMs ao switch.

Os comandos principais, em PowerShell executado como Administrador, são:

```powershell
New-VMSwitch -Name 'K8sLab' -SwitchType Internal
New-NetIPAddress `
  -InterfaceAlias 'vEthernet (K8sLab)' `
  -IPAddress 192.168.50.1 `
  -PrefixLength 24
New-NetNat -Name 'K8sLabNAT' -InternalIPInterfaceAddressPrefix '192.168.50.0/24'
```

Se o switch ou NAT já existir, consulte o estado com `Get-VMSwitch` e `Get-NetNat` antes de criar ou alterar recursos. O host pode ter restrição a uma única rede NAT interna; não remova um NAT existente sem verificar a quem pertence.

## 2.3 Configurar IP, rota e DNS nas VMs

Configure cada Ubuntu Server com o endereço da tabela, rota padrão pelo gateway `192.168.50.1` e um resolvedor DNS acessível. Os endereços `1.1.1.1` e `8.8.8.8` são exemplos; também pode usar o DNS da sua rede. O gateway NAT não fornece serviço DNS.

No Ubuntu Server, identifique o nome da interface com `ip link` e edite um arquivo Netplan. Exemplo para `cp01` (substitua `eth0` pelo nome real da interface):

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.50.10/24
      routes:
        - to: default
          via: 192.168.50.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

Salve, por exemplo, como `/etc/netplan/50-k8slab.yaml`. Use a sintaxe equivalente com o IP correto em cada VM. Aplique e confira pelo console da VM:

```bash
sudo netplan try
sudo netplan apply
ip -4 addr
ip route
```

Defina os hostnames Linux conforme a tabela. Por exemplo, na VM de control plane:

```bash
sudo hostnamectl set-hostname cp01
```

Repita com `worker01`, `worker02` e `sre-tools` nas respectivas máquinas. O nome precisa resolver de forma consistente entre VMs. Para este laboratório inicial, adicione em `/etc/hosts` de **cada VM**:

```text
192.168.50.10 cp01
192.168.50.11 worker01
192.168.50.12 worker02
192.168.50.20 sre-tools
```

## 2.4 Sincronizar o horário

Mantenha o relógio das quatro VMs sincronizado. O Ubuntu Server usa sincronização de horário via `systemd-timesyncd` por padrão em instalações comuns. Confira em cada VM:

```bash
timedatectl
timedatectl timesync-status
```

Confirme que `System clock synchronized` aparece como `yes` e que `NTP service` está ativo. Se a sincronização estiver desativada, habilite-a:

```bash
sudo timedatectl set-ntp true
```

## 2.5 Preparar e validar o SSH

Durante a instalação do Ubuntu, habilite o servidor OpenSSH ou instale-o em cada VM:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

No Windows, confirme que o cliente OpenSSH está disponível:

```powershell
Get-Command ssh.exe
```

Teste primeiro uma VM por vez. Por exemplo:

```powershell
ssh cp01@192.168.50.10
ssh worker01@192.168.50.11
ssh worker02@192.168.50.12
ssh sre-tools@192.168.50.20
```

Aceite a chave de host na primeira conexão somente depois de confirmar que o IP corresponde à VM esperada. Use as credenciais definidas na instalação do Ubuntu.

O script [`conectar-lab.ps1`](../conectar-lab.ps1), na raiz do repositório, abre as quatro sessões SSH em janelas/abas do PowerShell. Ele espera os usuários e IPs da tabela acima e informa a senha `123` ao final. **Confira e altere os campos `Usuario` e `Endereco` no script para corresponder às contas e endereços reais das VMs antes de executá-lo.** Não use uma senha de laboratório previsível fora de um ambiente descartável; prefira autenticação por chave SSH. Para executar o script a partir da raiz do repositório:

```powershell
.\conectar-lab.ps1
```

Se a política local bloquear a execução, use uma sessão apropriada para executar um script local conforme as regras do seu Windows; não altere permanentemente a política da máquina apenas para este laboratório.

## 2.6 Validar conectividade entre máquinas

Em cada VM, confira gateway, resolução de nomes e saída para a internet:

```bash
ping -c 3 192.168.50.1
getent hosts cp01 worker01 worker02 sre-tools
curl -I https://kubernetes.io
```

Teste também SSH entre VMs, por exemplo de `cp01` para cada worker, usando os usuários correspondentes:

```bash
ssh worker01@192.168.50.11
ssh worker02@192.168.50.12
```

O `ping` pode ser bloqueado pelo firewall mesmo quando a rede está funcionando. Se falhar, confira endereço, prefixo, rota, switch e firewall; use o teste SSH/TCP como evidência adicional. No Windows, confira o switch, adaptadores e gateway:

```powershell
Get-VMSwitch -Name 'K8sLab'
Get-NetIPAddress -InterfaceAlias 'vEthernet (K8sLab)' -AddressFamily IPv4
Get-NetNat | Format-Table Name, InternalIPInterfaceAddressPrefix
```

### Critério para avançar

- Todas as VMs têm IP estável, hostname único e horário sincronizado.
- O Windows consegue abrir SSH para as quatro VMs, inclusive pelo `conectar-lab.ps1` após ajustar usuários e IPs.
- As VMs resolvem os nomes umas das outras e conseguem trocar tráfego entre si.
- As VMs conseguem resolver DNS e acessar a internet.

**Não instale ainda `containerd` ou Kubernetes nesta etapa.** A próxima etapa do laboratório trata da preparação dos nós e da instalação do runtime e dos componentes Kubernetes.
