# Desabilitar swap

Desabilite o swap nos três nós Kubernetes: `cp01`, `worker01` e `worker02`. A VM `sre-tools` não precisa dessa alteração se for usada somente para administração e testes externos ao cluster.

## Por que desabilitar

Por padrão, o `kubelet` não inicia se detectar swap ativo no nó. O comportamento padrão simplifica o laboratório e evita que a memória usada pelos Pods seja deslocada para disco, o que pode causar latência alta e tornar os resultados de capacidade menos previsíveis. Kubernetes permite configurar suporte a swap em determinadas versões e condições, mas isso exige configuração explícita do kubelet; este laboratório começa com swap desativado.

Consulte a seção oficial de [configuração de swap na instalação do kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#swap-configuration) e a referência de [comportamento de swap em nós Linux](https://kubernetes.io/docs/reference/node/swap-behavior/).

## 4.1 Conferir o estado atual

Execute em cada nó:

```bash
swapon --show
free -h
```

Se `swapon --show` não imprimir nenhuma linha de dispositivo ou arquivo de swap, o swap já está desativado no momento. Ainda confira se ele não será reativado na próxima inicialização.

## 4.2 Desativar até a próxima inicialização

Em cada nó Kubernetes, execute:

```bash
sudo swapoff -a
swapon --show
```

Depois do comando, `swapon --show` deve ficar vazio. `swapoff` move páginas de memória de volta para RAM; confirme que há memória disponível antes de executá-lo. Em VMs recém-instaladas, normalmente não há pressão de memória relevante.

## 4.3 Impedir a reativação após reiniciar

Primeiro, verifique como o swap está configurado. Para a imagem `/swap.img` deste Ubuntu, use:

```bash
grep -n '/swap.img' /etc/fstab
systemctl list-units --type=swap --all
```

Se houver uma entrada de swap em `/etc/fstab`, faça backup e edite o arquivo:

```bash
sudo cp /etc/fstab /etc/fstab.bak
sudo nano /etc/fstab
```

Comente apenas a linha de swap, adicionando `#` no início. Não comente as linhas dos sistemas de arquivos. Salve e feche o editor.

Se o swap for gerenciado por uma unidade `.swap` do systemd, identifique a unidade listada e desabilite-a conforme o método usado para criá-la. Não desabilite unidades sem confirmar que correspondem ao swap desta VM.

Confira novamente se a entrada de `/swap.img` foi removida da ativação automática:

```bash
swapon --show
grep -n '/swap.img' /etc/fstab
```

O primeiro comando deve ficar vazio. O `grep` deve ficar sem saída ou mostrar a linha comentada com `#`. Se o `grep` não encontrar `/swap.img`, não há entrada com esse caminho em `/etc/fstab`; confira as outras fontes listadas no passo anterior. Após uma reinicialização planejada, repita `swapon --show` para confirmar que o swap não voltou.

## Critério para avançar

- `swapon --show` não mostra swap ativo em `cp01`, `worker01` e `worker02`.
- A configuração de inicialização não reativa swap após reiniciar os nós.

> Mantenha os três nós consistentes. A `sre-tools` fica fora desta mudança enquanto não for adicionada como nó Kubernetes.
