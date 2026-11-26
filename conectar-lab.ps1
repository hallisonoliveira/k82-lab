$ErrorActionPreference = 'Stop'

$maquinas = @(
    @{ Nome = 'cp01';      Usuario = 'cp01';      Endereco = '192.168.50.10' }
    @{ Nome = 'worker01';  Usuario = 'worker01';  Endereco = '192.168.50.11' }
    @{ Nome = 'worker02';  Usuario = 'worker02';  Endereco = '192.168.50.12' }
    @{ Nome = 'sre-tools'; Usuario = 'sre-tools'; Endereco = '192.168.50.20' }
)

$ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
if (-not $ssh) {
    throw 'OpenSSH Client não encontrado. Instale o recurso opcional OpenSSH Client do Windows.'
}

$terminal = Get-Command wt.exe -ErrorAction SilentlyContinue
if ($terminal) {
    foreach ($maquina in $maquinas) {
        & $terminal.Source new-tab --title $maquina.Nome powershell.exe -NoExit -Command "ssh $($maquina.Usuario)@$($maquina.Endereco)"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Não foi possível abrir a sessão de $($maquina.Nome)."
        }
    }
} else {
    foreach ($maquina in $maquinas) {
        $argumentos = "-NoExit -Command `"ssh $($maquina.Usuario)@$($maquina.Endereco)`""
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos
    }
}

Write-Host 'Quatro sessões SSH foram iniciadas. Informe a senha 123 em cada janela quando solicitado.'
