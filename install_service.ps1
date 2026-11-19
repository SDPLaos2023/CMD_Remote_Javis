param(
    [string]$GatewayUrl = "",
    [string]$DeviceName = ""
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    [System.Net.ServicePointManager]::SecurityProtocol = 3072 -bor 768 -bor 192
} catch {}

Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "      BB_JAVIS ZERO-TRUST - BACKGROUND SERVICE INSTALLER              " -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan

$currentUser = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges required." -ForegroundColor Red
    return
}

$svcName = "BB_JAVIS_Remote"
$installDir = "C:\ProgramData\BB_Javis"
if (-not (Test-Path $installDir)) {
    $null = New-Item -ItemType Directory -Path $installDir -Force
}

# Restrict directory ACL to SYSTEM and Administrators only
& icacls $installDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" 2>&1 | Out-Null

$existingSvc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existingSvc) {
    & sc.exe stop $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    & sc.exe delete $svcName 2>&1 | Out-Null
    Start-Sleep -Seconds 1
}

foreach ($procName in @("BBJavisService", "BBJavisTunnel")) {
    Get-Process -Name $procName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmd -like "*BB_Javis*" -or $cmd -like "*start_remote_agent*"
    } catch { $false }
} | Stop-Process -Force -ErrorAction SilentlyContinue

$localAgent = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "start_remote_agent.ps1" } else { $null }
$targetAgent = Join-Path $installDir "start_remote_agent.ps1"

if ($localAgent -and (Test-Path $localAgent)) {
    Copy-Item $localAgent $targetAgent -Force
    $srcScripts = Join-Path $PSScriptRoot "scripts"
    if (Test-Path $srcScripts) {
        $dstScripts = Join-Path $installDir "scripts"
        if (-not (Test-Path $dstScripts)) { $null = New-Item -ItemType Directory -Path $dstScripts -Force }
        Copy-Item (Join-Path $srcScripts "lib_javis_*.ps1") $dstScripts -Force -ErrorAction SilentlyContinue
    }
} else {
    $embeddedGzipBase64 = "H4sIAAAAAAAEAO29e3fbNtI4/H/P6XfAav1bS4klX+KkqVNnK9tK4m18WUlutut49VASbbORSJWkfNk63/2dGVwIgCBFOelzOe/qtLFEAoPBYDCYGQwGMy/2pqz+7TcMPudJGgfh1cXKWy/1b737s3jCdlmttma9PvBvgpF/7E195+ujaEwvUn86y17eBuno+mKlnfT8GKvbLw7DJPUmk4K3Z2FQ+n4/Ci+Dq3nsHwxP4+gymPg5pOWLQrwPhgAl9EdpEIU9emYUC8L0YuU0mkwOwxSQ8ACVERR4Jt+Po/lw4kNHxhO/H0z9aJ4eBeE89RMstbHx7TeNb7/59puVThxHcZtaOY39Sz/2wxEh1EujWQ2LpPE9+51DXTmZp7N52glH0ZgjdN67T4Cyrb5/l7bk84udnbP+m5cCE+hGEgEqOztL1v7MRh6Qk/3+2UJDVjv205YYgdMICHLkhd6VHwMAIMY8DtJ7IHIajaIJ9fm7LdYcRjH77sVL/mXz+62qAA/8S28+SbMheR9MgxTAbm69rAqjczeDupsbGwAlhbFAMq9cepPErwrhyLvTX8ixBTjPN3BICynWHo+b/fuZz5rtJPGnw8k98Z1o8PCktR9NZ7GfJNCz1htgS/6GNTX2YD14HqaTe4l+FdByIBZBMjH/MxsM9jpvD48Hf2v/fNgbvD/cGwzw8d4ef8J6117sj9l+fD9Lo6vYm10HozXW+/t79nbuxWP2F9aej2GA3gfD2AM61E9hNrJ2b//wcI2dRrd+3Lv2JxP2vLXJ1lnruNNn2627hiDaV+kUM/t0OQ95uWP/tvk37yZIul44jqZ79zgnxTjNUADW+eR+74dX6TVy7lZDTL/hPZ+/COJk+CtwE8NH5xdMlBblYppdWikL8ZZGt/tW9/gt/y15K45ugrEfc2AaF0nYrbd+SmjXOUYCvc/sMghBKObLHwTJLEr8uizI/8R+Oo9DtsaBAA8YZII2OJlgqLeev3jn31lEkoIShYcAHFyy+ko4h3Ft+r8x/gZGk76Q9JRNryTXniZ/3HTpvWtDwzDt9mMfliCJvU2Qay/BUUKQNI1Axr6DR/Uy4aZRkJBsZPAEVep1DviBvYnijje6lkMJ3Rm0+hFfEuq1u61ag31usOavIBGgh6VjgSjmx8Kke99PBOHfBHf+GOVL57c5SCmL/JzxYAldY+r7nnsc2qwJ0lZ7sMcftFuCx5uhDw/FLxwxQQQuHdWgjYPLS6D0Bv95CSDqKwE+eMXgb3OSZiDxydOnDaP3ojr/SwtAfaV9vhJcwI87xGcPfzh5tC4qAfIbDZti2YROvJ/8+1MviNWCGSfeMjOx13bOxPrWxvbLAvaDFlqnfpwESQqNH4b7ycxaV7R+/KjVxM8pKAnB6B/TCcM6CKofwS/BXBxIw6oSBzcwG7COq0oaz/Uan0tFQ7KYHXEFB7pxAr+PRqToQG9MbsyAnp/iAx90ojqsm2MvjYBegCjhdaGExunEC0Kcemta1Z+9SQA1/J6f1mv78xh0ofQs8ePaGqtR00cwD4PQr2mAeqNoRvqSXp7DlFJ7PJOFaF7wH8hKFlCdNuWS6cBLPUEY1A4RIAgWHZoku4/z5wvhaj0z5oZajipKOkVzSZgZbwrW8UWi+FSWRAwBsvgt1p81LlvWFKkbxuRFDfTGj1Oo14/2vMR/sS25VWGQm9Rn4ewP4jzZJMfkP/z3eP4z+Ccb5DcxaFXGMFs0t9Wp5XhPcYbGPos4cMEEkXhKbapEBJ5695PIG38N8fe3JArXlq7a9UfBLIDxgLUD5P7yAHp+CEsaLiOPqv63aHg41qspPRA0FTDKp7OzdETKnpoFmVIiC+/sHCbHMGAn8YfrACbczBv5dQNCw9QdLODnwAtkeuEgpqPj6FZTye7h0zw6ao7H/XfvdqbTnST5Zy1b3wTzeX4C67VQDnL2QFNoRs+EhbpyPfVGy5QPbhYV3Xyh47KEltL2E26SjrPqLcCtF/wbhQzozNpz4X4pn2L7wezaj7EoTve9fa3+qTe2nAUFs5SXEzBOf9rvfWdih6zEaa49P/wZHwc3ihIznBh7j1jXcDJJuTJKJQSSCuKpH44EDi1uUABE6kFcZFlocKByqx97YQJa7/QN6lJ7k2j0qa4hvMY21vQOSHW6TANDsJYGpmiT18z4lz8zgXgzvfbD5lF7f4e9g3+b3F5iEYhhVgf+e3hgI7XWA/sehmAbOa1XUONvpC3wVPXb7MD53vzykrwg1PP9aHaP1XivJXT+SwErqyoasetnldcciGiTcYkJg9QRxGm246v5FKTne9DXWX1NzusCDoCXigWwpGFgKqxLh5iqFY/lB0CR1YUwghGT+LDbAAYjlsKegWnSRCuEnbQ7p4IMn/x7IOjQOaQvtktoz5vjpBdA6IfydDhrCdSsas+2RL3M4uqEy4xOkdFVaG4B+AoWlyyJ2ohmH1nLpz7p/E9qrEVdMdHqWW91+6rQqOrkZ3W27kArL7ZNhcnWigUicuoGNwtrBDea7FtUWMwqTTIsrCLnQTbMIy+MwgAUTlzqtx6MBfqBKwkPvK8PvAMPHLUH0V4tY5decBX+kfyC8CsyDBW1OMbQl3R+SYIrnWGoLv6DempV75MiYwNsDC6janYbiwZH4rGILQnBIr6UjhbdQ3HD/4BKkT1LE/HMGPHs/a/RcBCgQcB5IHvhf5IViSuyF8GNfEF8kr0ARhAviHOyFyj9+QvOS9kbIIV4wwknKfLABPn6URM1BdaUDvdFhucX6fsrHWh0AubIl6j5j1XU+XaHPxb8+0hrQULJqf3kI8cNkU/+rdj72thwqPzNMEqZIgR3PMpfrRtyPW4Zun56HUe3rHYWJvPZLIrRvIQ60yBJUA/tbHWYL4Hd4KSOwlbNsEvJylZNCIYkF6fRGVejCk1RC1qd4h6C1oKQW2mSt0SAojCzsqbTpAFmyVkYIJ7eBEvJebeSANmw+pGXXkPV9jCp1/NWDWuKlhBQSh6QKBzLmU4dJUDNK6BxNhilXUvlvGXRPE1AcjIQFtEtkHmEaz0jgPWV3zNwn6EfNgH+zH724+DynhQToVwlxGk4CUMvxf2eoQ/qss/GPi2jMHwFi4dJM+M3Hwjzmf/J/A2rn/EbtF7jN0iJhlxvNKFd6rJQlaGCHDMYRNHpP3C14i1UXK9EYWvFcs18a1EhV5dYuAQQ/udLF681Vnk9Eu26N6cy0SGxdTH1YXhDHbE5z8GuZ+Etqto5TTtTy5ZiC+DBjCsO/D9U4QXwFfkBSxYqvHkNJjMgZOUDX2i8gh4VNV6qWjiOsh19u+nFdtl44lDNQCJBRTahSnkJbDhwTOOnwGvjLuS0dXSrSDeXyi0kwygy7CXdQiLXUDUuM/T6pfjTsPyXq4riUiH7H7/BY/wGvpDAR9TeV3YdGOKxXrxf3Gxrg9/cM7BquGYf9pd5c3QrpSDWSR2+9IIJTMT6iFyEKW7ko+7gx/44rxT8x5GpKDH2LW+jkKzF3kbD9Yn13Q5Hg/+dMw4/S258ZG2XMuQ4L+YVBarHNXR9b3wSTu57v00KQkrgjabilm8aYFlnyIJc+LGPM4bGw8Rv/jaP0KDgENkEwMRQfo0NSfUdRVOc4/AbLCJ4C+uUfATKse8B0lKNRKAzvvMV+1f+HWDX9YGMAiVQiFbrf91ZXX04/9fqRePJKu4hstVVVmtUgSBfQqX1j0/OPyYfexdP/vrxyTqBWRpGs3n+r4/xx/DiSWF99R24LpjWl9i1kRXLR6GNNgbzUjaNQIBGQNk0BtGCo5D402AUTaLwFVQnqQHmyegToDVE2wtDkwjbMOrLKja+nXBcX3212lDIK9Ujq9TCwDBg86Ree1UrR/ZoDjgO/asg5G7YXud9Z7+PZuiHw/47J3SG0phsRVb7V/2vQaPOKz1gjcbHYa20QZrbbDpPPbSS2DqbxdHIH8+BOeHH2Auv/DiaJ0gYmM7Ij4ImIB2GwXjsowOt9nFYPzzudbr9h7PTg3a/83AAKMCfo073Lfzonpw+tN/3O92H/W4HX/e7Z8f7+KXzj84+/XMGPw6P+ycPb7vt4/5Dt/PzyU8I5viXh732/k9np/Co1z/pwrO9/f2H3ruz/sHJh2N4un9y/Obw7Rm8OTntHHdPPvQ6ffoKiLR7J2fd/c7D3tn7n4AUD4Dn3WzwkMwGjXOv+e92858bze8HF09rBZTlZM36WkJK+RiV1vJ93CDoe8OJX+TYWelGt4mxzSlii7veLdpIytORYazCq7CqhuOP9YbaMod1ljSIXXjKy2kQBOjWYXIa+wl6/clbIuoA/87xEcVA6WJZxfGJgvaiDJCSIA1u/FMvBXlHrEIcOvOS5DaKxw+zW/gffjwkFGHxkEaf/PDBmwWg0OKfAf5NvEn6gDFxD7MgfIjS2cMIoP4bCoakKngTMNQfgvFg5MUcHHpvHmbXMNkfptEQ9IiH1J88+FMY1wf6Z+iFnx680Qg7NgijB6xJf29uHmAZRv8cNuvF9w+pd4d+AGnGT70EBAQSUFvQ96PJhIcuJLC4hWBejlpIkPOIlJELEGChf5vJNnROeMBZ9ZWYwVSX9DOIaw1tjOM6UhGmGr+MQDtFXICeqBxd/Pi79jZrCSb2jDfWOu1xJQkjHEChSgM/MZrmQo/Hp1O9FgbBWu9vyInCX4OZPLfec/QRhpxFOW5o4lonuohOMoRIz0i/zMv+znSWgh4OxbI990YjhzlnPcTNLJkvxd1Yyji8Stm2E5oi8zn16AL5+MmTJzU0PZJWbz5MpENcwWJbjvbyUTELWuh2Dtr7/c4BNuYAZz4qhm5BRrpYVbOfOmdlvN5qj8f189PePqxP0ZRzzwWBLXDnr9X12v2oHcfefb2Rc3pjvDWJRYra7oSabvrICBcCdBDEXyHApGKD42kQPqYiavqueBZ1REQ/92GUAItuCoBVdHPOPd65C9J9brds5F7ikLTBvhUBVJnvHP9Y9h3MVZi6kqZWbAxNXW51HdKhAfyXouehLIDHblsQWPNNFI98xTQE535aMbJG6Y8egnvDSfS3KAjtVmpUYACQW78mUTiR0nsW+zfveNh27W3nuNM77Cn/LEjZXbaZUUHrv2rO7P/ES8AsDxEJDFpHNQ/XTg27Zh9WG7bJmursCxpAVU5XGGNRrgdLNPKi0LL0DMRhEiNPqj6onSp00NBeVYHAlJW5+Ba/Wj5O3QGu0sUiVKO+o15BJT4unHNlJXz2VI6V/smJxOwghlVE8p5rO2WpwK6V0XTco0MFjoMLTZqi+nwVlYbR+B5mguRF7OUDx0XtYQu58kBy4iGTCg+ixQc1yx+MKf2g6CxZm2gsmipGUkMpixkggbxrhI8j8bXPLg2R5tJJBvN0pL+mbmUFxA6XVsDasPWw41kRKCBIkRWZomwzcEAiZe/Hw8FMyFDxXpEvKzTiozJIiBK03UuEzUr4QODBSLW1yxTJNSUYSD/wpDjFMvpgZOVwUIjPFSw5TFp7ajLIMmropHekeENZDdo8vXx5HO1FU6dHjDwyKIWkSDKj/VeSW2e1w5MWzAbfm36I0XdRz4Sc8NSvaQ0XOJqS2xbVRnlT510rP7VyW36ASKeOqVb0ZpNA8vlvk54yXhe6fVYm3EhaqNmLqplmj7WXdhqBmoQNagqSbj4NiweQS6a9eTBR+zcrQdgjX9Pf0dVk7dPAS6T6Pncq5V8KP7fz7YSMfES9JQ+bKTMmfxAHSrvO4IyuBQw8aqPrEFyHoZUlQKGuoNABLl4Bn18oBZedj669+GIjI5WkvdnL3EJ0fhMF4wuga6s9m/nhuA5YWWo6QQFcKUr+v0JynhTQzl5sRrn1+3MOO53MX4re6pNVaUIhDenR+qpz9c1BxoIOvQBGzfW0jDscfa1KDI1bv3ioVms2LeBRNVpgwSq04Oxnteq2Pstm4jIEs0gmB76ZH/hmfuDzHW027Z7me5lndu7RWoirE9P1PKZPqmC6/qQSpjZffgGqrrGswIT5of4Scr3K0waUK+51HmquDMPbrEOqYC0APFqB+MKDdj09svkx6/v+xPdiu7HSPpXQTYtjQsuotGMVO4SA7B7RM1tbMFdaW2Xo+kk0ufGlNyKNaN+vyBehn0HOm+nCYwuaCR2NOo3idCmPrl4xc8q6fK/2uc4jUzFG1PrzMPQnlv/oDShbQ2/0SZaHcn+f+/G9VUzTnAS4H21O6Pq/zcHaTyj1RTwtkHZd30NlVcercwdK2ihI2QS7ytBnC736bQ5mNyjSqFuMyYvA+vun673eUY95oxHoubUcz2kqUzpNE8KyUANs4u5f7uw4VZSO7qvUcnSvALXk5mF+jmc+1oQcrAQrN5FdG+f6hiTHKynwZ1oIOCiMnyEg8qlwmbGljgbTia1FFL/AO1rAifJTlSPlpyJnyk+eQzna7tLVmDUrnWPaPfInRJdsxSBPA6jgjRkwbxz4Cau/3mXbGNzgJ9fRZNx4xXiX0Qi89GNMYEHbe9Qxdil6XMHFa/4sobyD6kVUdBDcUao6navT2EHfzeYzfDxuEqdjWg9B01eCWBMv9FmQANFATICphtqFH16iUzFhp4eHDN3OIJprZdPAmggkxMU2BW5QJY1/fUye1P+6k21ff0yePpgb4lCi8eRrbHsaO57mZqfYvv2SUQep0rnzR/8z457XhQqGndwC69reM4782OdnbF+xOJrT9nQaMdEfPn9GvCkeMHQFiJaOujH4Dio6qJcljNEglxNuwZK5eHY4yHMchU2kiPBYuSmTw7UkEkZLDgXLcIACSRDihz/zv63eL8cnp73DHv/ZJXIlfEjZ7bUfMo9hZq0Is+w0yR/nXaEafu0lzL8b+f4YgAYpLokeNH+DaXOG8/GVn/KxCyNGz32WkmxMWrylP78uULmGUTS5WDnk0WZm/i16X5z4Si+l3Lwr70GCtAVmZ+kot01C73wuuPkaaG2mZKCOo9siL3JeuTN7wHfaHcm6mhOftBB3ShSClMdQqi7uSlmGGYFwk9lUEOH+CglY9R3I5ZTnnqc0Z3TVyv2rcp6SWQ8SYKXh8NeBN54OnmCsC/6IbkP40T49ZBj5hkw/w2hlPHWRCI3x4BRfq/OJn/z7hAqSVLiijR9iNcCbhcCPOE94Wqmjdg/E8qDXAcHcX8R3FXcBZwGG3DpMBHcWO6MITxuHG1dFpgSZAPGN37kDIwbq8BoGc61QoJiIE+To5KOSVBk9agjpXQfqPwDRG4M6hsZsNL+/eJp9b/If8M1rXl78/vKz/uvZ1ufGirlOWVHVxBTrJ7ehH6shxfBCL20xeWZgh4b9B4HG68EPqR96YfqaHqH3Hx8BF77z7+BbEly9Ng/frMQRbQeuHPHYrfPNC+Dl9ygU1dkXDvJwrBfbEt7IFdGM/u7ZRfVoNDWG1iapPrbaVqUf3uy8P9lvv2+fou7QBtVyb0AzKH+mKLcfW9TWEhuyGVrWjqygxpdtIszi4Ca/PZu1WeN7PDBlW+OZNwvU/ux8WKEalGrdTdWm7ojCXMfAVDOPyCxX1BIKSgQbJH/zrzkeFnkFeEfaJ62QH47wwAOUK8xg1FQJcTjMlpZaqcmztDiyupA8yHZjED9gRdKc2pMJQqurbq0pPBzbMpUAcQKsSQRluqgCcI4xyHS/z9ng8uRR+cZR5Xe0rTclB5uYoZRJNPmvdkCF2Hx7q2lr1iZ/BtkUZfk99BWw6ew9fw2vZte7tXf8F+2uk3BGsNxdCt9aV2rdIOeW0QWrgOZBM3Rea/tbDgTttRGcii62bAnjjra3Wsu0wmSxsLgD8ZTV1ms6ItJxXqGprJsNq9vVm4J6tes0nSU76+vDYfNXnH9NQa0WSJskSJv3wXQYea3bKP7kx0lr7N9wOJbMKFh4rUjJnPzQeMnaBuNs6qWetauOH48Wbfq6my3nlvUXTaSRssvXPPO9WuL41rv4ZbUjVjpexrM31/FzpSstkmHMIgnofON2yqE8OnxC40v8LJJLGWHXWF2nZn5f/MCfwVA8bzhEVpkV2M0I7CRyPyMwKyJyOyNwEZE1rVAUyRF5PxMpokjW+6yUlslPlOJyVoOTk82mtC6wFlWkiMjs9SbAYHBYYcK0orHokaEaQ89x7oxY7x2o6s9f4DF6BIh7/griEOyXMZqx6bXPPgThGCNsT3pMNP52HowtRX0l9m5JXZPyPHeAkXZOsBuoBolYV6kA1d799P5o52Pv5E3/Q7vb+XgUjOIoiS7Tj/qhnBprUv7XmoZGbZnwLUKCy3T41tLAkHSTXbBf5rdEsoSKpkxfrJhSG5YYUqQjPXT/5Oj0DAyi4/ZR54GenHZP9ju93kl3cHjQOe4fvjnsdE29VMycwnCimszYC8bW/rsd3mLN5jEwEKJPwnJ8D9ZwmPhkjHKPTjmXiYJkPqa+N2UCADcYr/DARUrctD+J5uPLiRcDY5G45+YkP9eaUJEgSea+sFOUhUJW5uT+69iHArmvZSM6LD8R76m1pFbM6Gw2y8ygzBCkKrolSCPWPOcHIy5+3/5c9L3c3tNHIm/n8Ub+AZ/sn7zR8/8Pa4sA/d+xtf5jS/2xttTXMZUIxNBLfC5P/lAl/4sVbo5sNL4nrc1UiidcjiDvykdKMzajMIVKMdBVil1WL9FhGvnKdFwla8ZeGrMKampomFmKV6VIzZjHNmvp/98BFT/4wy7fB89SkKvhBLILqiTrnlgBVSgywGsd+el1RGv76UmvX9PeCB8uvNrktwaoN8hTxLPFRYShS+INYHsz3LynZXodDe1XDGPyEj/dBUZsvpTNykSrGXvqKeTFoDfyzagU+ByCijukchSgSaUBlqAUj001TjhjQR5vqrIF48llHWBDDzyl8qArYLSp5ggDxaXrU96LYj2Tp8VQGCWzKLQOKsfj8qhaHAGMqkVYOhDZryK/S4YdNEHj2I9wippty2694sjKn6ZGqbMhsGDnbgQGFIzvhdHZW2RO3uCgpcq0JL6W9itK56OaqtJDAFiCJATej2N0wpRQJU8Z2ZRBHB2iODEhYOc9OlXtAoI3Ta5k2KsAza0E/qM1BTHhXfncBWI80uMQXTV9xEGvRw8yQS3xt2IJhAYnNTcv08J5IoYdQjkfe5PVXRnYPuRYpKgTPFrkA8ucLVhB6RD4qyXOgLqUTQeq3CgBRX4eypQToK9THrUdhYe1bUBuDECzYAuryXdSDGxYU9PXlWRuZrpTpkYVuhnahq9HA+70NOwKPFv9Ml+DKpU7L5HZBAXrJ98FTtCdI9Dx+ZOBlzo9EqqtfcsnIf0I2p0txx7t84JQ6UWjT7Akp1Gzv38qg2KWuqrl+dOG20uxn4xI35QXMIySEeUvtKyAD4fHB4ddMOilvY9wP75BEw5VkxfbH2+2WxutZxvPNr//CDCADn6Bvxgb0PdaeYufs/afbS3d/jKtP9uyWof2ROtiiggIrE7EU43QjTcM59glel1aObO8EyYwFJyufJA6d1YsZEWzdy8I0XAqsR5EiUebVry+066CrlMZYxBEeTAAte5pdAZCVq00SmrZvkTSi+Yx3aD14+q338wpZyBf1V6ZP11nSuwihyf2E1iVHY9afEIlrldquuXeOvPP2IXQwMg9u8YwN3hQ+KLV95JP2OC336A2naBpwQyqffuNGOjRxEsSNOyg/Sl/pJ8yw4wUI4Z6/BEYeHXOUOcXzIuvEm1xthQLx/VZqrvanWB1+xnyVoNuCnsoeImXhxW92/x+65WJB7I6YioPhL/eZc/ZX/5C2J9vXLBdUCdpXyG2A90dYV1IhNsEg4FRZQjTFs/3SLA2Lxqv8jVEmpkUivjpu4g0Ziq+deEojfB5UXcbz0rbwJQNEvx2IfhU3FNnEeUF+6vd2vOLBtthmy83NhywhLTrzsMeUa/O6bKmdXVN68saR29NtG934/PCQdu2B200wZR2FQdtIoO4lxy32yThpnvxmLmo/8xVMKPYPqFeV0itiXYEkRYRB/vjX3mje6y7mN2Jctjpfnyv9XvjYg3Tf2qgGotpWcjOm49h563K7OwkaBk7P8+z8/ZS7JyR5euwtLiDsUWWiXb6snaGtsQOy62CjEsl9gOfWK/ZDxka6od8g4i8Zucck4uajUth4+J9vnE+u9gPikdfIyLIpKq5XCuChroENkJ8xUqC4YOEUQoKdJasTiwszFuTHDAsXl2IzVEMkH7y8MCG8kdDokGuWQtDkbRwiHu+0onbMlOaenavZJ1hcZ2hXQfRG3qSHf+0C7WVo6MEPWRoecOa9YpOeOJ7ccgzYD8w1QL8xFOeVPVhF5s+Dy7Yv6BV+FswSrwdsyHXaGGb2azIFsC1vCxYsya8KiJNwD6fL9m8LR9gTcr8CSPSt74DjXyjtVlDgZa9lMFluOcRB8BT9QaVJ9a9hgIV1ojCCdKnZhiCAcphf8iWTSNYUqIZBh+3cvNAo/KzvFAwH/RHMzzFjMonm8gvwMn+rf6qfnja5smQWu9Fs2tiHOzGJZBWDygEpCiQBFoX3x/2+p3jw+O3TFF4BzPquOFLACfztPVmMk+uqQmzDNdI6zi3Yxxp/kX0Cr/XB2z3NZhM3D2ooRzN0AOUba3CjLsJ4ijEMO4WHvmvb+D7NcbvehLS/wnb3NjYWGPCado6BEM4hP5VWNBur9GGrlt35pVUwA+g7X5RUB4/MJp82Qe6wneghup2e4TOO1UgN2YGvli5dRwd+BMPzTxEvKQ4NwdYKolPP+swQYD878BanPh8YouWCXrxemfM40YZmnhYbg+49CqmaIKFeKYF7Co/n92PiU2WHgo6nFW9oUpHfxaJUTyI6aK4xRaPlqrFkjRrYTzkjIdzx+p+jqMd5ANTFn0W3OsL6Iovu4IneS5RcggXK3XX5E1OuEsY3cG4zfKOP6xLkK76uB5wGC0zC1kGkTbLOC7Kl8xH51Ve7mo43Yok0g6yaKUwKS5HtLioOn+okoviEalQ63WLTkPWYS6CSvE7q+GZphrKMx5kQm9PZtwj0fWn0Y1PvcR0XJgbrrqIIlVhfEdiJvRBIo79u5PL+urOatEUQwpjjR928eCCPFZcUFh0UKSmoyay7GsgiQFQIwt6sJfncqA8n50FEzF7yjYl0JI+cJzIqh81b/1hwj2dn/z7WkONNbRRAIKc8wYcHPkoDv5Nnm2AYXCCG1AZu+GdFjAfebxUAaf/ycnqWcMNMobVTy48kw9Bel2v7fleDKjVJE/hXicQPonC1kk8xj22w6sQGHXfS3ILJH4KGEpDW29YDdB3JUPjJEfhjKYxaqBS/yeXlSDwyK1GlXsiFPp5iP3QlXpyeGdafe1dv3+6vtnaZNsbm+wslHzgj3HWiv1RcZXfDtsQD8Xl9Dt4lUbi40Oa40UcK2We2B/lSNH+KP8qzYZF1TNVzF1Ml4ruMkJULsfMHqkuPzsngdACe+/amyy59jZxawe+t+Rd3kuPmLjmG2EZqdSLBpBP9qestvX8Zaf9pv282fl+c7u5/d1Bu/n98/12c/95e2/jYP/l873NzVqhPqP6CG2LfbOWdQETZVurSjrVm3AMXfnkl7CgG6GMMTeBMXt0MAlJLT2hCV9VHBlkqPbZ7CqGybvDlHAsL68ztahbXgFU8ma2xcS12x2GJkVGyqd87SucG9a8UMSiqaF+lcwOx8zIF1IaETe3SvRvKrlY7+bFBMXqbj3aBd7UrcZDpVtxgKZula/Os9uyWzLqMI807xJ/7OwPOWFIRKFEl86IfDlhQAAa0YfEYUUsO4eH80sBhR482/ruxUuXbw8/jzGzhD33J941h4ipAAM/qD+FRH/BRqis1gF7YkD4u0AwKzioSQidqszukB/KAl5XA4kqLc2ADwltGiodGdC429giTMAYbrwqspDwU/CqzKYyEjXqHxGks/S4KFZbZAhyj8AyVHi5lvETOrXJQ+DMOOluzDIZFlV0WYgFEgOmTEU7WBTOjOBCT0UxZ5dYAtEMcycWkF3MTBGeIeyyPKVxr4DDKdO+FZTMNcsrka8RBqt8GiAIo/z3BVO4hNWWYp72muy4+qJmdtmcWmAfFdTMdW8zR6Ct3JON5UmgjYTaE2FFcBbAwo+Sgnw1VhTbyBOtIqByfRU/S0y//KMycWPne3POdqecc1CJixCkN9cl/iR3IYQmUEWqLCWGivKnCD+T0Mtt14qpXyTczVLoMkK38w8oFl5r63X2sL65sbVtD50QT7gy8gwIP7DNF89eblfbn8XNlSRbaFH7dTIHbawA6A21j1LgikE8MAFZHTFu5DZoZLu4c6hQLmhvpDZRoeQ55mrYph3ozWf6s2f82Yb+bMtRblOUqy7ARUfzNoIwPhD/LG2p2wop+emmY+HGHQ5P584DtVIy05qm23FnJd3mULK3gyvS5WXip46NLsFH4v0POVgFhJL6WqIpahzGGgcBpOe/i9hKamkl+3P4EYg9hUlRLlcEHEsAOenKyacvuxltcdnNlvBiosolgxZZ9xbm9TjWde9cNAN5nrLxhcahxhrbapRNNtUulMXQjL8gAm9sBJBz+DUEGPODRTd50ZcbtFlnc8EkQvcp7f9rhb+z4SLGVApm1NaLxVwiCMFTBRYTwk0MqLWIGIQ6YV2H0kiOH35goPI8YOV8jITFMcr1qLr03WO75LSpCrr0smKXXGETrm3pl2I7WhAC/+hUCBZQQRIAhDyqQvj1NSwltMm3tS3+2Bg7+R0ZTrj2JV1yYVHYmmBMENImdUT9Nbado5CzvUyDVu0hbRrQBVezvGcb+XaVeiVrlw5Q1oPFzOIaLlOBE2MnHlIYwa4kxHnA/h/LUdAt9gSAKrtihnKeCb5M6KkFZuylXqUVRrgej/xpFN8LkFPpvtCf5ryQDqJNE672klLC9Yk6Ci4MQhTSjwu9hnP1JRVCakQ5IVXQZkG7vNuLl3j8KGkiGt9lL54/f/b8ke0j5gXKuos+otHXr3HeI3XevCn0r7rq8+olFQs6/NjOfVeE3JxWormQZfSLj0JBeWOGfYcz7DWfac1mw00pgg2Eqgcg21AWL9frbITRwlNN1Plc2RDaj9MFyCfVZcw38aba7UCubVABl4oTYPpWYvclBUbeAgtGBBwJX6wRvLlmhmWuGaGCpTvgj42xUU1/eZjNaffkH78Mup32wS9WoE1hI1VibYoDWNzWauUZksUNEH6PjFmRdauFrGDMegsG34hQOY2ju3s9ZJbiJMyI2YqTpSBepMhlXeCo+ioBIV5yH46ow45u5mn/SNbnUNRmDKPL8h4Z/6HOGDK8/adzVxoHwYUg3i83nXEzT/34gW2rH0+fVl+P7L6MgGyUtlDMZet9IUuqei0ZadFTp1e5v6Reaxt7/mtM7arDdHXGaBcSckGn8OPdeoHWHbl91EYOwVARdhYHdT7ujTW274UjfzIhzGjrG6ZWWOiTxQ8NugJfUnDJwCj8cCdVPeMN/+4RHlvJT/7dwq2BjEzqRppH+ezxQ1HEiiufNcRIkBQiaVV/vrGxxDqMhJb+P37wqy669te/EosqMtVrb/it2mmErmQc7uxUnsjD2nJvSZuuvHQ0U3uFStYu2i4kqZPihrwSuFwc/W/e0rul7ZGUvOKKVPQE5rEhA5eAjR/pOuKDrwhKjiQ+B//4bT/eNnbRD8fZxCd1rOdfYfir8L1KXEIQBYoMR/xEMh6Bau0FoReD0cqvglpeWnzN3UI+ZVXnyLkNysxsLoSb6gC9wcGcJ4BgPPUm+GQeQw9qnZM3teKOlM79z2X8v/Uf/qePAtb1R35w43f9ZD6haHc1KW7RrUovF/HmoxYo/OCMwdPOGisbPdVZnLil2sSSYPeViVRefgGt8GPLCZ5jxhAUqsVFvXbBI02fw1tU/b9p019tyvPlpdKmVsHU01bYD9d+2A7v6+kmCKutBcenvtYuHSzRaosOuLqiDrEsAZzp7uG/1R+/UlpfzKKd0KVzUD13klsct7YPe+u1KFOFeYydqpinv2XOz148YgtTIHEIBclAeJYMDRxdNC3PalOWDKNPPL29SrVn5C1diHYekhqEjCRaKaP2wsSXspsS+cJMvAkSzU6LoBXg+X3+wkuuh9EkuorYegQK4jT4t/+UrfOYsR08j7cOhXfUOXp5NH7r9V82LRq/x4zq/zjs758cdIjIG+5kYJJH8lfV8owFun46neEKlDskuENdcN4ChH/U3ZC8pYLUBllOwDHXXP7vZTcYXRbnKRhl3StJIUEAXLdKiVcW+66MJyJBocz1dRWk1/NhC4ZqPWtR+zpej/2J72GuqglmakzXx9FtiB56vVDzlqf7bHrT8YttPRWDNwusFuFJS2s19kGOVmw7y9UgQ7j5tb00HPyNndnpdtSeBU5JKRIscOPfrtES8Q8UClDDtHPNNt6NQRa9yDu4vtXa0E8IrgC2IgOaAHIgSCX22wUxGqWppGVV89ZUTsuE73zLhlr0IAFwsCLCjBD9+x3zOtEhBLoVr3yYKMtZz8dsFrJ+800QJymz5QNvnScqou+tcXCF9/e4HslslPxi3h1500C7+ebi9xfbucsGXGNafAmALjG0dVSwRjqdHUycc6qu02KAHplzzNQKghq4A7/RmROZ8vi41jCPprygjHktgK+ytd2OqrIWFF2Wp/KsrBgK15c6n8xrosel1/Bi1dw1vNqKppHeujVtlM69CR8RSsWHLdM91IK0nNrN9uQqgsXueoqR+jDijRYWcg0c5yUFllbzoubxww8zcSkrWyNRukyuLplMx5SpKpsxTMXgUuTCE8my/qSynZqMeYXqkEK/5CK7I4W1SakDHzUZ3pRcAPS1wZbfnzEP02DQOT4QyXjfH+4NBtgKv4oGz7lMJiJpiuOmwZVAlBjFwUzd03va47+7UYRF9cmiv2I1UXuQiAZmyaaeMlLlfxQXwupN5TRF47W5oP6FzZBREsoW1TyOVO4uvClqjsQ6jSbB6J7t3c8w5wzxod03I6eX9h1ojrhTGuiV7Lu9Zhprs+AYR/ezrEsqvbDMvkREOAuDhWMyD79sVFT9auNiN5cbGavAVxkbC2YVaju7VULvx9tCK4F5hRNIN7p/ni+Zl8Fdjd/q1E7yowi1BXolqYpFUiRKbK9nKjar5rP35iDXxJOBeSfGypj4+Cf/vgoMXthIILwyHoqBTCpBGA5mongGgi6Qz3U/X5nKYYUhX4gXFIdSWBhT7eIN6R6YDXEVHEWFVnqXapSmVeJ9dFWVzpRssQUmFWmbaezN5GTgMs66+4uUHxvaoutHnIZGDgg3bqtbGrk+iYXS8jGIxJW1c9KAym59iGqk8lzQ7pWRLFS7rQQK/Ff8X2HNbCRvDPOLhJU1bI3OGqFVYBEX3IIi7ko1rUPjEmBtETCNQ3XnV3yFGrll/pVnWRZ19Mx9/NHi602q3qACAkQl33/b7nc+tH8ZnHXfG20WFaqGRRHfVbo8Z3Qpr2VQl+fkxdqj79BB6DStKlAKyuq37JTdbmuVzd/P4KBYsXPOzZGiqUdl0i6+kO9gaN3GZzHxMQXW6NcMhNC1Mp/GHy1qVqYeBn38+Lub48ylZyG7+eGI531Y4Ec0wZYlF55hxnlhq5+Fs+LM9PyNP+aHdhUqMi09FRaJyS1mWYl4ruGsqUXMn11CPaNLqAFA67THVZqWuPsEczngUAF9z1dmLRz5C2ql9bM3mfsVWJRXVRUFsyjv8K30YOAIluU/lyNzQr7ISsn9JfQS6i3yoeaGmGNgjXXBLTgHw+xEMp/7BRNKtGHNqxOgRByMkenD5VYMo6Yuw/UX1W/O0NDjE1d7gAv7gX/pzSdpkbwvmX1fd6r90dNsuSnG72dTubYLZte5TsyLopubq9Xmc1JbaIoc3sL8OdhjUtCv6oBWNRMIOjmaJ2mEebF4nr8WBj3yC3lF/up57GdLxiU680wLNV/KYaMuZkNVO2NE45E4ENqkPGy1DigKMdO6SEXqfuuqRelhD/YatepTID+VLQd9Qrkdc+3jFcw5IYBRZ6sm7qtg/6HtNwIq8VIabPQJalMEyI+3mrYOsYVoJiyDpHXkgc3sTaAHOpx+tNfrd1H/1ZPYiesOHBJqmXZO01gyW3ueRnXC1LhPMLsqoTrUf8LzN7Hvc7wNkOKPS1VpCneLwRFNsdy4espBkbgXQ3Z+8tMFwR7zi4KbIBYw3TH+3mMzNVXMkcOdJ0s+1Ug98flZ6v1oAuP9FjoU6kqbdCnsqUtXiiyJJtf2dRcTn1jlLCsAN8wZpqWpQwsswXRHMBD8Xm1bNsMLf+xia5WnXbsoS2DHwCQQ06xQK/XvvOkMpICmjzZqpuSsZLUQfnklXKOpLFRF5TZ57BEE1kSrNnxBAiNON7iPW+yUHFba2wjFasqchlXRpeziCjQBBU/PmnqFtkVcbVPyLA5c94dl98K87fSdN4ztReN7uR+Wuw1dJDnkWW83n7vqi9sFEvLY7XBXKc+9qRXGnDWpRxe1d+7S2BPbGrq+r90Hg8GxrOINOdBvq2Z2F47ovfU6u+1G7x5P62gVddyQs7DOT74/a0/w5oPCK4nLeRITUln39gnQgmrntX9wAdOEojVSydWFoYKYmV1w/YkMA53qgOJ9Ut4CVCO4ejV66NgJKugSz69F7FXQnUddLkQQSi8YohaLmyu7ZEiWV1GuqnLRnUMkLxz2pwKy6C4i3fhybMNZwHK31NhbSK5bivD6nFxfXLcVwUO957yI6xIeo5JITlfxmiOZDqPgYiMeDrgr4RbdbcRf5qihtVDwknqUeyVVdN68IOn/wAVJDk5yjEzJ7UjOul9xgBRUvE6o0lgtHLNKY2fTubiEcnVKBC1/nCOITvtq3WnkmpFC7ZaTqT2M8EiWy3XymV+II3RCVBP4DbyML5LscAziKEgxa1y3125ubWy/ZJ/k5bzmgqpuvHWss9YbdX+Q+RjvWPTHdEWQWnZNYPtkIworrOJale2MCmNO/VYX2C51Dbjun3530uuL28DtxyZwWUS/tY/luodXOfLbFfN0PJUXL9ZqyuI1N20MDfy/3Tf6xd53ed3VH+V/J/hOT3r2uiV2FMUlyHn+tosV3G/vgMzdG/wmR3LVLMe1xdMgD786UvyCcL0BbWoaZarDFLShU2ED2lN1Ep2PuUtSLOVSK2qzii9byMCSvsxIIg3oVs2ksBu2h9tRt8Dj7Yank0aXiS7XuNMNt6CDJcHZbue67WnV9+irbHOc8it1FzlfdbCl2xwA7pHuV8LEyRoLhUiRqFboaBf8ltaUglyrKC/eLR0J0zpX9xNvHwRXQXoaqFvJV+Ih0+8vBmETTcnwYCI7L9sSJXlq6fr5HCzpzRcXUBNztDST6wnmKWiC3sD0d5sXumuJ1dG0BM2gTnD+H/sefjYaBkcq72y5tLMEbWaMOURwvuPUzJKNiPHTWvo0YyW3PheO/qdZbtyLxhuLmiNdtopbk6fKVlQdO1G8u9VYJBQXblNZM1Rg574u2rHtK+9A4wEt/PSWrbPkySHZTe70QauwVMjgsvwSglUqbdw5Vh+3aHAEoOG2O792Vb87U+kF2eS3/U765Zd4i4p+tTNbcLuzrkMUgM9Ug6zaFCPAzM8ujwbLymQRBDoqwveoCXhSBixQtu6Qo4e+Lu/KAcxKGSulDVRfALMq8xkeeYY6qYZHadDPPXyaR0fN8bj/7t3OdLqTJP+UIcmuK7EPwDy+Zs95gUUTI6emrkkGcW3hyq6995IU43xvwMACfJ09cHlkhVzhs0hOIHEqkvtcDRki8pHVdO8UklzMCPMNpSpYMfIUqF9NMKU3tQeYGMla7QWGh+OJ9Ef2rucpnq04vOQ3uY7NCjxuWjZwlYrjOTm5j7JBRt9/HP++/dkRak89q7Zg6FXsODJBr+JpS6XAuBZu6R8daFiCYBE0/Igwv8GIz9Zdjki+nCU0SgWG/FiCo4rQsHoir5S3q55qN8srgla4YV6jYzLje/OO/YbmWRwwtQWCOymCSuvCtwFM0BS+dH6rPGvSqKjhaWq+8M3nDN3RBr8rHMQd2hKdL7tEm7haQuUb8+KXuPSa4nFRXIA2kH41TqahdiLkyClXgJ9kw4SkgxszQ3oU1MxXE3GNJWjlj9pxZ5SAzMSg76hhct/6nekSGaJFx/rOQtzywbYwUCC+8ZnH5mEA7bDt5hiprFo/PTxm3iXuS25uyHwtSctEwXKilqh2+Fm0rORChdeAy9uH3cPjtwPAZpckBEapHnR+PtzvDA4PdlfyyjQW2O922v3OweCsvw9FyhbK1Wi10agVRazqPdT3tHe/ysexoX3gxZ/2773Q3azBX2q3+J+d7kmz3z3r9RknDBNEY93O388Ou50DkzEdzf7iTya4+P6v6mvzNR0bggmBrMgY3iHRPI5AKtDFSo5gAO/eDetcrHIX5SEEThSEVswDXWAq1ovWkgar55amhqNBstHK+jwPMT4IwFOfEz8cD2KiA6yV0ylIr9bQQ80eDSXqV4UBLbI3hDTUFJgjkKZkO6NykpvCOWwxQqVJrn/CFgGxVGzNusCCXsvqKEtITXfRxxzGz/9jTKmbpVyVQ6dDtoMs3xZqovih9HDN3sT3YXUH0RyF40S6I+RnaSWyaE8qoQQqj9AueMV1zkyaioEBCqZKsSFVCjw3pEUN/AjG4j+aQkdv8jWoJp0+Yu10uOYEykIZyfBf5JySLK3VF0c45O8W/yYPz3rQh3EtV0g32Ar9k2ZDFXzm+aIL3MmcFC7ncAGuC92gTv+2ApXzcZcDMZ2yGRiyYM3eXZgN8RJCmV7YXpHTpHhYNC9tTnnA4TGOneZPIlU5grpovKpZtS4IxgqFS3bn4IJxWvNAUKIeW12pO2jeWDXXxx12nlubQBliF0gkHG196ZJc0Wi0Fq+I+kc/9Kd/CrcVCqenZhe8jULfbRM4qQSKDSeTVFKFdG6xt5ia0kvpYjJKyCRVWijVarm6ai+TrgFe0iChquaCkWUgsT8OG8FBzgU75NnanjWLzE/AWZFDHfcdye13eHqzLYlvx6oEM3li/NhPVYJU1hRf3njTYHLPCEL5JHrIdTKf7ECDD72ZBJ98funzEym3C4q8+L619Xwbi312tGNlRYAFFWCJXSlEXQEU+RLsQ+7BTA/1B4I4chbgb3loKLum2nJ/cT7iJJ+JjV81AKaXDFbVOB2CLZgXKKBH0UZYVoGEj8/TsuTiCIIEb03mEchScZHv8D5raEcEUdFmdBYdp/jkjFyPwgmnECs4csFTuKGPLQpRSS9KggBrmYgk1bQRvsCBGpIXY/K8rA6ADuXm3VFLuqKWdS890rVEZ54HwD1urARXOHuyjCtKnn6dKqeaqe5bpfloyQ+U5uNnoQ4MObhWA/8Ffmf5sbzqZR71ct+aLCXjOoqUXslvme/sLHOdSVbS9dznGuxq81Jf6HXRYApdMpSaWh6lvXtYWNxziRc4lGn9MynvmvcUSumBfgbaeT2r6thOSjV6GyDOVbULbdJyIZi2Rpd4cnykHenMHmKWEBQzFG/C8BZ33IwekVSF7mkF0bNdSefKiVcDmdvEgYx4uBgZWfDxyFSMnUpbaOgOkt8mg3mCt/ZWPQ+btsZDzBQQNhaHEf02oWNnrmBCZOtWDwpQBhv6pk5r6I24QVJaSVtVXxlNuS0hyvCY733ul8gVnncoB5pNiFbXn02wo7ULzJpzcWELCGylJYD2+dUmtcM3rPOPw16/x+q9zvvOfp9tsjfdkyOW3CctzHY/hJUEBjYIR8EMVjH24V2n25FXVB+jFm2Px2qDHXRPTtlZr9Nl54TtxStW2hA/rPW4Zt6fvAVtVbZjO+WFCKOu85Qc/nEU/n3ux/c5uirq52KPC06LOkUGN47qCwWN0iF0g7eK2ZNXOrn8E04NqbLIiIQwui0RqlnUUQprOyjWP9bd3aJQemPe8HR/AL155RfJPgB60eL6czKYp6OcPeIW3U1JPIYQcuq5JMDKaOJ7IZJRCJldIxuFi9CW2Hbpc5ld8QXEqd6v5YSfI1AhPygLNgy40C/QQJtC2axFl5cTEbfgsJNELIML8CK1wfCV/RoNS1RTzWl2AEKj3zH9Zs8LU4U+ApOFevKjkCmyEyt4JyV1/8w4s7EobI59FN4ilXkCuuylH7P02meB9BDHDM8sTvDhPb+wEeOx+RTMzw3TyhHeBLciRLe95bzXj/PXOLIcKb8TzRmNLpIazUPTxZ5zuTvc4k4PvI1qUReaOgV4/82+Gz6Uw4P3nSamCL1gx5TdkwYKSO8JkBQUUeS7h/+U975FwoPcMJhaqoeppar5WTDpqSkRs3fWYUosUt+w4qw0Tehc3JICRfuojKDaFkeT/XZyGM74+TDNYa+V9sbjAc9VjZFvaFDU5Vv+uHMDGPDLOeKL34V6vpJgIFjD0QP2GQNejEyGSwbpiXAuPSBEd71K1vZ/04bXFSOTC0bzwzGGkPNTt3+LhuKcSNHxRmmBQMnDseuAIeHD7U/Xay6YcycXkVT7eJ+X9kI7hUiRavoBEXmIUM8/oJcqjmLKZbiAr8BV6MsyIuVOxY1tPEqOQGitNbs+6HioOouYRr3fuJsTjv1Yhka6AyabRELGKVmcMXRlRkxjOjMs69xlnvtAURlAI4pIImeFMH/vxM+ix77QgOcHsgY+9GMSzcQpNqSutH2LRuVFblS+xvK7zmmbW/hO2/39d8rG5/Q1g2NyCYm50t0EM4m0bkok5zbNxfl3LasIVIJfeM/lxUrXuz2g27c42x95d93oNnEn8uHBt743Pgkn9wCEYfMMwTkPQO/h5db+eIcRcquE5yost5N7NvPjaZAm/FQ5QmPceln/cNh/R8zko0RNWuwMVlpeH5rBXq+SxKcbsxPteLREV/aANScynXT2CNbZ5xgHjUqMfLiLj7R0xaPHGahmBiTbhThymajSPB2V2qaGeamOET/bKCghDNBep8/63fZxr73fPzw5Zoe9k/dt+va+83PnPcOrvdjZ8f7J0dFhv985eMWwxvuT/Z8G/cOjzslZnyjFH3dPPuyfnB33FdFeUfY1TNAGVNAQ8cbeLC04LJgnHz5p8xp17IPe6XFSDAT/6elBTMocFe1jwM6kDjCM05t8sH/MJYYdJ60+CnVDGxNKm3p3vnHRwp4XamximLlTu25WBLViPg0xaTKoGh0wfYydBP6WIjY+27ZzOp1pZzOg5ITzW9Ki7aNg1MIb4c4jAncBEjL0b20DPDO3xjEdgcl1yh1IxjPdnEfxGLMnXPzoumsggz0i0EiA4hNFuKYBEucro4uCEtAmvpXx4zesGSSwAuyhLnKRHYrLzu3dVLxjHSlJSZDPT3vc7c2H4AKbtAhmx5wKzjEX4yAgGsK6i2/rBD+72JpOwiGf7kgB69wME2azvSvAr0jc5S1zjjML4PqBa2Od41a0iG1rxwvytpPrcCpPhofyiB8AoC1PlFs1Iv5I8+Po/eAv8umeC9cs0vEfvWZRKHc8JSA5P5DxcvGqpFYVkaAjQaNuEozwkjMOaUBrzS76L6z15uusFSsp3iZWkk/evXjwWvRuz78Kwn7shYnHW3jcIqNBIIfN3aJF6EX5ImQvDpeXPLn1Yr8htE2wwJhynLKXgKz9C4uL0ztkWeGxAHhdEJ54T6Zx1nrJs9t/6PTg0VckXU7CA/JIcCPZnCMrwg5Q3EP3buCNnFJqigIt/mYww8s6MfsSKXiOl5k43dx+9izbe0knRxQSYAJNJ4Mp37I/P/LSa77LW9/c2ljLHnh39c01u0FRUTt1/WxDb4wniZHNPiHukm/3ZBJftyOOySy/CrSVGrnfOTplteFwQEmIBpjtN2uaiAzcCODFPR+agxGfN0XzEg85+y+NSvnLQfL1pAUVR0PfKTgwSwS/QwoWae2+Vz2LhAoDAFJnt79uNHTg8qpX8ew2EQxiAeqE49OIhonXoq1deDjDh40WVrKgRjMEKkkXfdoTqVRKjzQ+2zJoLePF6vUMgls3yiy9uy2YY59hYf0VUGM1dR1CKl2/oPTC9+bSVyy8zLoDVMKNul0xFdVOHIZfiYT6GU+046s52ig4RDyTMyi+ktAqrsKYn0b3BcuD1feBbsjopfegTrwLxmM86oZJovrX8TwzSy47cT6ltJwYNUWH1uhSJJIW1RZ1iXOx1R0OjTVhSW168zTiR7rg9xwMXMzptbO+nt0LLHpdQyfEmFITQGvh2IvHtFWpIV+tr7x1cYdLzXjYhaUukTnJdF/ZCmD2Bn14bXvXH6SRCEKhcmMwOSkk2+lagJklAl/rW/L6cREz69gywkNXCqChbBihtEdgjgSJiKd9trFhLijG3TqcTnnLAoa0T4uqkYEhoytPvLDUGRixFa1ozS0e0ZC8TaUuE7ide81/bzS/b148/diCRTW71uIjXqnTKDgmo4+kdruKo2Th8LmCEl0nZhZ0RGMcwdwjpZGVIm9ynDs6bvHpGReKTo7SKYFyK6XTscQ5uCG47US1vP18voBc13j0QRHLvtxQC7URo5qxX6XbUbL2FwQUSDI5AgocMRJcxC0RIJHfTioCzReELwOduwaGgZ0x+iS5cByMKdWqD8ou85gxtXBmUS5FDLCFVW/rue7xknLRn84wh6MhK+EZpRnUno2HIvRCPjHUOn927U/92JsM4giDARaGcihwZamOm3oiTtVWdq8DaxrZiFWJbGoOEisTaq7PXKMDrB+18htgZ5WUmc2XDmwEtc+FIY77OxFPbSEv4uLAKePkn7xNO6BiJoNPBKws6mQVo05WV3NRJ3OtxlmlOJXHR9/wwbYD44oOdpRE5FCBZaJyZAXbv8nPzJlRKoycx6ftXu/DSfeAB7ggXVfX2P67zv5Pg9OT94f7v8CLkzdvXjEBQo+nYW9OulbkC2u/70OB7sn7DjsHzsXgHZ6K7IK1Dw7YUedoTwvIcWSxWSZYpjCHH374DrOgmtMAtUJt3IdYRBnHbW+EgbZu5C1rNe5/jBwuA/8VZDGBN6x8rceZRBWBNUX77bqOKJR4aYwUROvISEVrz4w/l8G/u5ktkxWRsYNMFuFUyArISEdVgI+C1oge3aXLi6yIiKzLYPDpnhXQIo14gYxCFu0cDs0KvRRF5jy/xa6mNubK0IEirQzZUnlM5eahhukSu4YVaKaKzLjgV4LbdO6oWOF4jkHrPGTYTKLnuEdGlNY3cAuuksESRizcgmtkRHktZMu6tsu9k69F62og8p455xEsUSNL/Wo35iBOhTYxrXOsB5o7wNiNy5YLNG+C2Lr00UwZU1ydpYCDufciv+2T3Y6D1TEC/s7IFmV0PJdgtfoBSJ6DZV32qfTso6ajyCsL4i/KnOC4ysA4L1f0XL/zRg5qvdbttWFkySyvOZJ3Q13EuAyYrdtU4AGacUyMD8KHr6+YNtyFcaGu0YbK+TG2Fp0yDpcBrZK5YWxO5mnzWG0DqAlatI/Cz9P9LRoWSAceEUPxHAc+EH6SZK4uj7cqPapZkezMHioUjufG6VBH7iVPk1q7ZSKtKXqukKkqxbQWGsWRY73O/ln3sP/LBeDwK994+BVIxanCLoH/2Tz05jB/4uDfPsWUxT7OwrE6yijwWnUFiXX1c85W4F3WEe5j0agoI1GWwnseJsFVCF8o3CdFFTjryuOQs8VQybUpKu6oI6NoXB3SA5DKo4zkJaciJElEK+lso4roAUkg7Ly73if/FsWb4URbmQkMK93L4tBqC+j/t4xdkP4ekNFfH/sUmZbd2roDyuSjhmDZTFNUZ8rzH9GkFd1uUW4CnK36A/c0zUIfswmr7q2w4WZ2ugE9e7xIFIDBg/YakKaNtzHa8Lmbgem/8xCNGiL+06gl00y4cOHk0jV7Hm8GmKi0+9Ft0s52JrNs/Ik6sseSdMw3PGu1V/jDj7m3pXA6EdJTdbcnmXqO26dH4maSZZwo2WhZvpNZRd/JVMU9mUzk3Q1iHgsiNu7sNxlZn2f+QAX2ty55TpxxadkVLLLHPHBMG/gsYKIuNvnlS1BbyOhukAAg1GUfLBSsoSSUWqN89IQc3JYaV170VyNzg9ZBxYfZkIqwgf8tg2p13RlpUWkU9OiJ3FAYARG2BpYjap1mjjxim8xHaMvDBEJcB3owgIF82RnKfBBLwehw09sxOOlheBmp3TDXXntTLney1+5uksmHwBZRQeCC+QyofEvZww0ew+6LkwWqQGbDNhy50CR0KYOqkoRcQkV0WXisRnKAQn6JbufqNvgBinGrMvI9P21PAi9xjGhJ7u3iFULkfzdBVUvosfB8Dz9KvpA+1B+ZKhNTnK2WJGtarU6qLj8nX0wp10H6/K6WC+Mr3HMU1VmCRtN8sswoHkS3IQ6IA7d4pg+YSCA189LrQovPmUc/npFrQ+y5iHwjCCa7zQ7z081queVL3ghTmAZbXA4DLRQQCsX3QJys1KCc8pAYWAveCHG/EMiYy5eSvQTCdqEAVgSHQV6pm9fGMP6r8tidzb7ayK2MKZKnN5sEYtzg35j2s+NZfpCpeHYW2ch1/oibEsbFd1QrHsgIj7aDtY0jeqpGSuun1dHiDIKKmeRtPovHkg9A4UjSDXTxrGRA7ZH7s3YOisdC1rtgaKKJzXzSH0DbyO2Q6XPkyAu9K4rTb2FitSldvdTKoGa3bFXbOTq/iYIxaBsJedhJWuVU/2JqE35CnQMQ3KPm3E5CFxkpaHUqz/0u4kZHdTtcwaU1omIdm+CXzSQtHuSyIIBJD16i6PnypvIqKse6vChXCgSe+aJc4bcQtyLaDSNpM5/cp2R/CkFX2FUqNMONlnUXaa6D+hVJR6AYAhvaxjXlMCGzsxtFyvR0RA56WGaJ2EEqXyty5wpJBAzM1SnCoEOe6mZbtmQj1zT9HLZfDAwfJIqQxtl1l7rZoG+P5uzupjxnpZGY4taV1m3o4HlfpruvUz/1CtIs/xoN9UTru6JvZiHpUcwKGY5A+VkyR46VUH2X080sI4TJILn2tp6/YCJrFA1Yjx698+9A/XUR02LsfFaaOjFaRmdxAJLV1NE2PWc99yHVjJMfXyeNjLl1QExblI9ZDaQjq0yeDVZIBKjkSY/rLgdVdNbTNSGcjkKBhYGSk9v1k5hSoDzGDUdUqGwDfPvNf3MaUGf+XVfu3W7n6KTfYe23neM+q3e2OsAl/bPjY3E07JeGrFxyPvp/tG9mvt3ChILFGQNz4OgrN8u+RubcAqT7WTopZ5LD4hy8OVDytl0OSsz2why1X5pUtyyZ7ldMpfv5v52vvv1mBbOGiWATEkPCs6IteCIGuDDVTCaXXVljsrdLpc/VN8lts30p+95KAoyf87f7qJ/zE4XWjaDZD2cSp0SNLcr/Z8839M0YifcjWK1Cogwjm4CBFViehA75ruVBlH0/mKDyXa8XSHm0NAQOdQdeeJDPsQyIsAA9Rtahw4s8/ogWBg48EyeP8wVdVDWO0kDFNdFDRzu2im4PFyn7+QSG5SlicvboUpcqqzbzdq249XKE6jud2QDdat3H5BVNXqug6ZLLi/NpKQpAaLcw6+QuKO26vNmsljfaq96Vq40Mq3xXrmik+nWsyaKrWFfQgbE3v7z09SvgUN1tcbN1bx5MMNRRHSw26xtSUVzQChbtyaW4bFZLeVcqM+WnXHbKz9IpyPFTEvZTkDPREX2/9bJwAj/KL4yfzzZRaWDECRX9atz38MjlK3g0ObgFgTJ1RZxfybLwFtTAcvxoWfIhSK/rNWSgHeaI4VE9kdGvGau12rMZKP7UHwFRhWW/cLl1tJ1gfpkCeiRlnl0NrgjQdh/OVwjF3q3Mz6LVXbA5ID/CR6VV3J/AYBcV52uAaFDc5SJ/QUdqSJzibNKELslGnnM+H7tFWYOEFMggVz8HlMNVtlaKE+GVBV0YFVt8r/Z3Zj7Rr9qVHSrIVa5a4CfnuA1oHJBeXENEp1Srpu+D84QD5Q5OM4HAQkrZTRjJ/nEiANdJZpZFnGFCpV2nXQ57LPChORbcMw8Mzs+Hrq6vOkM3FjZnjo3onmiMUMmAgqLxmFOZy6OiDbpz79b1cWfcK/pol8nGEb9PVo7YsnfI2h9OQqjLr46V/KAelHJNVmppxpEfe7YRTPetY9XA6KOh8FsOWEHC+aJPRYapUGxBkQWv+Qk7jZx8lIwnIPxzVmelMVPXx5NeIA56vJLKpPZA6ZT6o/I758s++aBT6aQz+qUNfI4VFjfiMsR1+IshPFoNsz8VeK+EagWvFueqcSfc/MNGu+CIz2I9/FF3Sf5R+vejBt1FaYcijtbwEpcUVU68movYf55vnASJRIALEfFL6KiaEul8b6jqv5dp6Yj3Yg3Tbn15RZN3CRv7uoqWY2XGVh61LH/lpVh/Q6FJjxf+xUJYg66L4GVWXqfwXUIN+D8vegtWQ+etaCun0WRyGKZ+fEMiKr+/jelVrc1yVyJZKPf/AUyb7L/HVgEA"
    if (-not [string]::IsNullOrWhiteSpace($embeddedGzipBase64) -and -not $embeddedGzipBase64.StartsWith("__EMBEDDED")) {
        $gzBytes = [System.Convert]::FromBase64String($embeddedGzipBase64)
        $msIn = New-Object System.IO.MemoryStream(,$gzBytes)
        $gzStream = New-Object System.IO.Compression.GZipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
        $msOut = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 8192
        while (($read = $gzStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $msOut.Write($buffer, 0, $read)
        }
        $gzStream.Dispose()
        $msIn.Dispose()
        [System.IO.File]::WriteAllBytes($targetAgent, $msOut.ToArray())
        $msOut.Dispose()
    } else {
        throw "No local start_remote_agent.ps1 or embedded payload available."
    }
}

$csSourcePath = Join-Path $installDir "BBJavisService.cs"
$csCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;

namespace BBJavisService
{
    public class JavisService : ServiceBase
    {
        private Process _agentProcess;
        public const string ServiceNameString = "BB_JAVIS_Remote";

        public JavisService()
        {
            this.ServiceName = ServiceNameString;
            this.CanStop = true;
            this.CanShutdown = true;
        }

        protected override void OnStart(string[] args)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, "start_remote_agent.ps1");
            if (!File.Exists(scriptPath))
            {
                scriptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "BB_Javis", "start_remote_agent.ps1");
            }
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Mode fix -AsService";
            psi.WorkingDirectory = baseDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            _agentProcess = Process.Start(psi);
        }

        protected override void OnStop()
        {
            try
            {
                if (_agentProcess != null && !_agentProcess.HasExited) _agentProcess.Kill();
            } catch {}
        }

        protected override void OnShutdown()
        {
            this.OnStop();
        }

        public static void Main()
        {
            ServiceBase.Run(new JavisService());
        }
    }
}
'@
[System.IO.File]::WriteAllText($csSourcePath, $csCode, $utf8NoBom)

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
$targetExe = Join-Path $installDir "BBJavisService.exe"
& $csc /nologo /target:exe /r:System.dll,System.ServiceProcess.dll /out:$targetExe $csSourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $targetExe)) {
    throw "Failed to compile BBJavisService.exe"
}

& sc.exe create $svcName binPath= "`"$targetExe`"" start= auto DisplayName= "BB_JAVIS Remote Agent Service" 2>&1 | Out-Null
& sc.exe description $svcName "Zero-Trust Background Remote Agent for BB_JAVIS" 2>&1 | Out-Null
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/60000 2>&1 | Out-Null

$cfgFile = Join-Path $installDir "service_config.json"
$existingCfg = @{}
if (Test-Path $cfgFile) {
    try {
        $parsed = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $parsed.PSObject.Properties) { $existingCfg[$p.Name] = $p.Value }
    } catch {}
}

$resolvedGw = if (-not [string]::IsNullOrWhiteSpace($GatewayUrl)) { $GatewayUrl.Trim().TrimEnd('/') + "/" }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_GATEWAY_URL)) { $env:BB_JAVIS_GATEWAY_URL.Trim().TrimEnd('/') + "/" }
    elseif ($existingCfg.ContainsKey("gatewayUrl") -and $existingCfg["gatewayUrl"]) { $existingCfg["gatewayUrl"].ToString() }
    else { "https://bb-javis-gateway.apisit-yimboa.workers.dev/" }

if ([string]::IsNullOrWhiteSpace($resolvedGw) -and [Environment]::UserInteractive) {
    $enteredGw = Read-Host "Enter Cloudflare Gateway URL (e.g. https://bb-javis-gateway.example.workers.dev)"
    if (-not [string]::IsNullOrWhiteSpace($enteredGw)) { $resolvedGw = $enteredGw.Trim().TrimEnd('/') + "/" }
}
if ([string]::IsNullOrWhiteSpace($resolvedGw)) {
    throw "GatewayUrl is required."
}

$resolvedHost = if (-not [string]::IsNullOrWhiteSpace($DeviceName)) { $DeviceName.Trim() }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BB_JAVIS_HOST)) { $env:BB_JAVIS_HOST.Trim() }
    elseif ($existingCfg.ContainsKey("custom_name") -and $existingCfg["custom_name"]) { $existingCfg["custom_name"].ToString() }
    elseif ([Environment]::UserInteractive) {
        $inp = Read-Host "Enter custom machine name [Default: $env:COMPUTERNAME]"
        if ([string]::IsNullOrWhiteSpace($inp)) { $env:COMPUTERNAME } else { $inp.Trim() }
    } else { $env:COMPUTERNAME }

$existingCfg["gatewayUrl"] = $resolvedGw
$existingCfg["custom_name"] = $resolvedHost
$existingCfg["hostname"] = $env:COMPUTERNAME
$existingCfg["mode"] = "fix"
$existingCfg["updated_at"] = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")

[System.IO.File]::WriteAllText($cfgFile, ($existingCfg | ConvertTo-Json -Depth 5), $utf8NoBom)

$localUninstall = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Join-Path $PSScriptRoot "uninstall_service.ps1" } else { "" }
if ($localUninstall -and (Test-Path $localUninstall)) {
    Copy-Item $localUninstall (Join-Path $installDir "uninstall_service.ps1") -Force
}

$pairFile = Join-Path $installDir "pairing.txt"
$svcErrLog = Join-Path $installDir "service_error.log"
if (Test-Path $pairFile) { Remove-Item $pairFile -Force -ErrorAction SilentlyContinue }
if (Test-Path $svcErrLog) { Remove-Item $svcErrLog -Force -ErrorAction SilentlyContinue }

Start-Service -Name $svcName

$hasPairedAdmins = $false
if ($existingCfg["paired_admins"]) {
    $hasPairedAdmins = (@($existingCfg["paired_admins"].PSObject.Properties).Count -gt 0)
}
$alreadyPaired = (-not [string]::IsNullOrWhiteSpace($existingCfg["device_token_dpapi"])) -and $hasPairedAdmins
if ($alreadyPaired) {
    Start-Sleep -Seconds 2
    $svcState = (Get-Service -Name $svcName).Status
    if ($svcState -ne "Running") {
        if (Test-Path $svcErrLog) { Get-Content $svcErrLog -Encoding UTF8 | Write-Host -ForegroundColor Red }
        throw "Service $svcName failed to stay running (Status: $svcState)."
    }
    $savedPin = if ($existingCfg.ContainsKey("device_id")) { $existingCfg["device_id"] } else { "configured" }
    Write-Host "`n[READY] Service $svcName is RUNNING and ALREADY PAIRED (PIN: $savedPin)." -ForegroundColor Green
    return
}

Write-Host "`n[STARTED] Waiting for service to generate 4-digit Remote PIN..." -ForegroundColor Cyan
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $pairFile)) {
    if (Test-Path $svcErrLog) {
        Write-Host "`n[ERROR] Service agent reported a startup error:" -ForegroundColor Red
        Get-Content $svcErrLog -Encoding UTF8 | Write-Host -ForegroundColor Red
        throw "Service $svcName failed to initialize."
    }
    Start-Sleep -Milliseconds 400
}

if (-not (Test-Path $pairFile)) {
    $svcState = (Get-Service -Name $svcName).Status
    Write-Host "`n[WARN] Service status is $svcState, but pairing.txt did not appear within 30s." -ForegroundColor Yellow
    Write-Host "       Check outbound HTTPS to $($existingCfg['gatewayUrl']) or run start_remote_agent.bat to inspect." -ForegroundColor Gray
    return
}

$pairRaw = Get-Content $pairFile -Raw -Encoding UTF8
$pinCode = ""
if ($pairRaw -match "PAIRING_PIN=([A-Z0-9]{4,16})") { $pinCode = $Matches[1] }

Write-Host ""
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "            BB_JAVIS SERVICE INSTALLED & READY TO PAIR                " -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "  -> Machine    : $resolvedHost ($env:COMPUTERNAME)" -ForegroundColor White
Write-Host "  -> Remote PIN : " -NoNewline -ForegroundColor Gray
Write-Host "[ $pinCode ]" -ForegroundColor Green
Write-Host "  -> Run on Dev : send_remote_command.bat -Pair $pinCode" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor DarkCyan
Write-Host "Waiting up to 120s for Dev to run -Pair $pinCode (Service runs in background)..." -ForegroundColor Cyan

$waitPairDeadline = [DateTime]::UtcNow.AddSeconds(120)
while ([DateTime]::UtcNow -lt $waitPairDeadline -and (Test-Path $pairFile)) {
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $pairFile)) {
    Write-Host "[PAIRED & ONLINE] $resolvedHost paired successfully and is ready for remote commands!" -ForegroundColor Green
} else {
    Write-Host "[PENDING] Service $svcName stays RUNNING in background. Pair anytime using PIN: [ $pinCode ]" -ForegroundColor Yellow
}
