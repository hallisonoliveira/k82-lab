# Organização dos guias do laboratório

- Documente cada etapa ou subtítulo do laboratório em um arquivo Markdown separado dentro de `lab/`.
- Nomeie cada arquivo usando o formato `[numero da sequencia]-[descricao_em_snake_case].md`, por exemplo: `1-criar_vms.md`, `2-configurar_rede.md`.
- Numere os arquivos na ordem em que as etapas devem ser executadas. Use números inteiros sem zeros à esquerda.
- Mantenha cada arquivo focado na etapa indicada pelo nome; não reúna etapas diferentes em um único guia.
- Conforme o laboratório avançar, atualize ou crie o arquivo da etapa correspondente, preservando a sequência e a convenção de nomes.
- `proposta.md` é a proposta geral do laboratório, não um guia de etapa; mantenha-a separada dos arquivos numerados.
- Mantenha `lab/comandos_kubernetes.md` como referência transversal de comandos úteis. Documente os comandos de `kubeadm` e `kubectl` usados nas etapas e acrescente comandos recorrentes do dia a dia de SRE, explicando para que servem, onde executá-los e quando exigem cuidado (por exemplo, operações que removem Pods ou reinicializam estado).
