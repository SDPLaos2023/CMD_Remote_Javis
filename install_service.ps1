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
    $embeddedGzipBase64 = "H4sIAAAAAAAEAO19a3fbNtLw957T/4Bq/ayl1JQvcdLUqbuVZSVRG19Wkpt2Ha8eSqJtNhKpkpQvW+e/vzODCwESpCgn3Wffc5Znt7FIYAAMBoO5YTB3I3fG6l9+weA5j5PID64u1l67iXfr3p9FU7bParWNzOdD78Yfe8fuzLN+Pgon9CHxZvP0462fjK8v1lpx34uwevZDN4gTdzot+HoW+KXf22Fw6V8tIu9wdBqFl/7Uy3Vafijs9+EIoATeOPHDoE/vjGJ+kFysnYbTaTdIoBMudGUMBZ5++UXjyy++/GKtE0Vh1KLap5F36UVeMKaG+kk4r2GRJLpnf3BoayeLZL5IOsE4nPCGzvv3MWCsOfDukqZ8f7G3dzZ49UL0ALoXh1MPXq5Y+yMbu4Am9sfHTDdktWMvaQrMnoYw0CM3cK+8CADAIBeRn9wD8pJwHCJBPN36Zoc5ozBi3zx/wf/Y/nanKsBD79JdTJMU1W/9mZ8A2O2dF1VhdO7mUHd7awugJH6wQDSvXbrT2KsK4ci90z90J1Nv4BNdPNva2irBWGsycQb3c485rTj2ZqPpPdGTaLB70myHs3nkxTGMrPkKyI1/YY5GHqwP74Nkei+7XwW0nIhlkMye/4UNhwed193j4Y+tn7v94dvuwXCIrw8O+BvWv3Yjb8La0f08Ca8id37tjzdY/+9v2euFG03YX1lrMYEJeuuPIhfwUD+FVcZa/Xa3u8FOw1sv6l970yl71txmm6x53Bmw3eZdQyDtswyKmWO6XAS83LF36/zo3vhxzw0m4ezgPvFiOU9zZGx1vmjfesFVco2Uu9MQy29EZfcJxMnoN6Amhq/OL5goLcpFtLq0UpmONzW83Td7x6/5b0lbUXjjT7yIA9OoSMJuvvYS6nad90h07yO79ANgdvnyh348D2OvLgvyfyIvWUQB2+BAgAYMNEEbHE0w1TvPnr/x7jJIkgwQmYcA7F+y+lqwgHl1vN8Z/wKzSX8QV5RNr8XXrsZ/7Hjpv2lBw7Ds2pEHW4vsfRYh126Ms4QgaRktEu8NvKqXMTcNg9TJRgpPYKVe54Af2Ksw6rjjazmVMJxhcxByVl+v3e3UGuxjgzm/AUeAEZbOBXYxPxcm3gdeLBD/yr/zJshfOr8vgEtl0M8JD7bGDab+PrDPQ4s5wG21Fwf8RaspaNwJPHgpfuGMCSRw7qgmbeJfXgKmt/jPSwBRX/PxxUsG/zrTJAWJb77+umGMXlTn/9IGUF9rna/5F/DjDvtzgD+sNFoXlaDzW40sxtIFHbs/efenrh+pDTOK3VVWYr9lXYn1na3dFwXkBy00T70o9uMEGu8G7Xie2Ve0cfyg1cTndDGa+uNfZlOGdRDUIIRfgrg4kEamSuTfwGrAOrYqSbTQa3wsZQ3xcnLEHRzwxhH8NhyTAAOjMakxBXp+ii88kHXqsG9O3CQEfEFHqV8XimmcTl0/wKW3oVX92Z36UMPre0m91l5EIAslZ7EX1TZYjZo+gnXoB15NA9Qfh3OSl/TyHKbk2pO5LETrgv9AUsoA1XFTzpkO3cQViEGpDwECY9GhSbR7uH4+Ea42MmNtqO2oIqdTOJeImfOmYB9fxopPZUnsIUAWv8X+s8F5y4ZCdcNYvCiB3nhRAvUG4YEbe893JbWqHuQW9Vkw/5MoTzbJe/Jf+ns8/Rn0k07yqwikKmOaMzjPilOr0Z6iDI18llHgkgUi+ymlqRIWeOreT0N38jnY349xGGysXLXnjf25D/MBewfw/dUB9L0AtjTcRh5V/cdw1J3o1ZQcCJIKKNuz+VkyJmFPrYJUKJGF9/a68TFM2En07tqHBTd3x17dgNAwZYcM8HOgBVK9cBKT8XF4q4lk9/A4R0fOZDJ482ZvNtuL43/U0v1NEJ/rxbBfC+Egpw84QjJ6KjTUteuZO16lvH+zrOj2c70vK0gpLS/mKukkrd6EvvX9fyGTAZlZey/MKuVLrO3Pr70Ii+JyP2hr9U/dScZYULBKeTkB4/Sndv8bs3dIShzn2vvuz/jav1GYmOPCOHjEvoaLSfKVcSIhEFcQb71gLPrQ5AoFQKQRREWahQYHKjcHkRvEIPXOXqEsdTANxx/qWoc32NaGPgApTpdJYAg2I4Ep3OQlM/7HX5jouJNce4Fz1GrvsTfwX4frSywENszqQH8PD2ys9nog324AupFVewUx/kbqAl+rcZsDOD9YXF6SFYRG3g7n91iNj1pC578UsLKqopFs/bTyhqUj2mJcYcEgdgRynFZ0tZgB93wL8jqrb8h1XUAB8FGRAJY0FEzV69IppmrFc/kOusjqghnBjMn+sFsfJiOSzJ6BauKgFsJOWp1TgYYP3j0gdGSd0ue7JbjnzXHUCyD0Q1k6rLVE1zLVnu6IeqnG1QlWmZ0ipatQ3QLwFTQuWRKlEU0/ymyf+qLzPqi5FnXFQquno9X1q0KlqpNf1em+A6083zUFpqxULDoil65/s7SGf6PxvmWFxarSOMPSKnIdpNM8doMw8EHgxK1+58HYoB+4kPDAx/rAB/DAu/Yg2qul5NL3r4I/k14QfkWCoaIZijHkJZ1eYv9KJxiqi/9BObWq9UmhsQE6BudRtWwbyyZH9mMZWVIHi+hSGlp0C8UN/wdEivRdEot3xoyn338LR0MfFQJOA+kH74OsSFSRfvBv5Aeik/QDEIL4QJSTfkDuzz9wWkq/ACrEF444iZEHJtA3CB2UFJgjDe7LFM9PkvfXOtDoFNSRTxHzHyuoc3eHNxH0+0htQULJif1kI0eHyAfvVvi0trYsIr8ThAlTiOCGR/mreUOmxx1D1k+uo/CW1c6CeDGfhxGql1Bn5scxyqGdnQ7zJLAbXNRh0KwZeilp2aoJQZBk4jQGY2tUdVPUglZn6EPQWhB8K4nzmghgFFZW2nQSN0AtOQt87Kc7xVJy3a3FgDasfuQm11C1NYrr9bxWwxzREgJKyAISBhO50mmgBMi5Ahynk1E6tESuWxYukhg4JwNmEd4Cmse41zMCWF/7IwX3EcaRRcBf2M9e5F/ek2AihKuYKA0XYeAm6O8ZeSAue2zi0TYK01eweZg4M37ziTDfeR/M37D7Gb9B6jV+A5doyP1GY9qlJgtVGSrIOYNJFIP+E3cr3kLF/UoUzuxYtpWf2VTI1CU2LgGE//Opm9cGq7wfiXbtzqmUdcje2oi6G9zQQLKUZyHXs+AWRe2cpJ2KZSuRBdBgShWH3p8q8AL4ivSAJQsF3rwEkyoQsvKhJyRegY+KEi9VLZxH2Y7ubnq+WzafOFVz4EhQkU2pUp4DGwYcU/kpsNrYC1l1HV0r0tWlcg3JUIoMfUnXkMg0VI3KDLl+Jfo0NP/VqiK7VJ39r93gMXYDT3DgI2rvM5sODPZYL/YXOy1t8p0Do1cN2+rD8TJ3gWalBNg6icOXrj+FhVgfk4kwQUc+yg5e5E3yQsF/DZkKExMvY20UnLXY2miYPrG+3eBo0L91xeGzouMjbbuUICd5Nq8wUD2uoee5k5Nget//fVoQUgJfNBG33GmAZa0hC3LjxzHOGSoPU8/5fRGiQsEhsimAiaD8BhuR6DsOZ7jG4TdoRPAV9in5CoRjz4VOSzESgc655yvyrrw76F3PAzSKLoFAtF7/2976+sP5P9cvGk/W0YfI1tdZrVEFgvwIlTbfPzl/H7/vXzz52/snmwRmZRiOc/7P99H74OJJYX31N1CdP6uv4LWRFctnoYU6BnMTNguBgYaA2SQC1oKzEHszfxxOw+AlVCeuAerJ+AN0a4S6F4YmUW+DcCCrZPvbCSb19ZfrDdV5JXqklZoYGAZkHtdrL2vlnT1aQB9H3pUfcDNsv/O20x6gGvquO3hjhc6QG5OuyGr/rP/Nb9R5pQes0Xg/qpU2SGubzRaJi1oS22TzKBx7kwUQJ/yYuMGVF4WLGBEDyxnpUeAEuMPIn0w8NKDV3o/q3eN+pzd4ODs9bA06D4fQBfjnqNN7DT96J6cPrbeDTu+h3evg50Hv7LiNf3R+6bTpP2fwo3s8OHl43WsdDx56nZ9PfkIwx78+HLTaP52dwqv+4KQH7w7a7Yf+m7PB4cm7Y3jbPjl+1X19Bl9OTjvHvZN3/c6A/oSOtPonZ7125+Hg7O1PgIoH6OfdfPgQz4eNc9f5V8v5x5bz7fDi61oBZjla07GWoFK+RqG13I/r+wN3NPWKDDtrvfA2NtycIma4596ijqQsHWmPVXgVVtX6+EO9oVzmsM+SBLEPb3k5DYIA3ezGp5EXo9WfrCWiDtDvAl9RDJTOllUcnyiY3ZQBUuwn/o136ibA74hUiELnbhzfhtHkYX4L/4cfDzFFWDwk4QcveHDnPgi0+M8Q/43dafKAMXEPcz94CJP5wxig/gsKBiQquFNQ1B/8yXDsRhwcWm8e5tew2B9m4QjkiIfEmz54M5jXB/rPyA0+PLjjMQ5sGIQPWJP+vbl5gG0Y7XPYrBvdPyTuHdoBpBo/c2NgEIhAbUNvh9MpD12IYXMLQL0cNxEh5yEJIxfAwALvNuVtaJxwgbLqaxGDpS7xZyA3M7URzutYRZhq9DIG6RT7AvhE4ejihz+0r2lLsLDnvLHmaZ8LSRjhAAJV4nux0TRnejzunOo1MQg28/2GjCj8M6jJi8x33n2EIVdRjhoc3OvEENFIhhDpHcmXed7fmc0TkMOhWOpzbzRyPeekh30zS+ZLcTOWUg6vErZrhabQfE4jukA6fvLkSQ1Vj7jZX4xiaRBXsNiOpb18VMySFnqdw1Z70DnExizgzFfF0DOQES+ZqulPnbJSWm+2JpP6+Wm/DftTOOPUc0FgC8z5G3W99iBsRZF7X2/kjN4Yb01skaK2O4Emmz4ywoUAHfrRZwgwqdjgZOYHj6mIkr4tnkUd/dDPcxglQKObAWAV3Zwzj3fu/KTN9Zat3EeckhbotyKAKrWd4z8Z/Q7WKixdidNMbAwtXa51denQAP6XouehLIDHYWcgMOdVGI09RTQE535WMbJGyY8ugnvFUfRj6AfZVmpUYAiQm7/FYTCV3HseeTdveNh27XXnuNPv9pV9FrjsPttOsaCNXzVnjn/qxqCWB9gJDFpHMQ/3Tq13zgB2G7bNHHX2BRWgKqcrjLkol4NlN/KsMKPpGR2HRYw0qcagPFVooCFfVQHDlJU5+xa/mh4u3SHu0sUsVMO+pV5BJT4vnHJlJXz3tZwr/cmxxPQgRqaIpD2bO2WlwK618WzSp0MFloMLDi1Rfb2KSqNwcg8rQdIijvKB90X5sAVfeSA+8ZByhQfR4oNa5Q/Gkn5QeJakTTgWTRV3UutSGjNADHnfCB9H5GvPPk2RZtKJh4tkrH+mYaUFhIdLK5Bx2Lo48LQIFBCoSIvMkLcZfUAkpd8no+Fc8FDxXaEvLTTmszKMCRPk7iXEpiU8QPBwrNraZwrlmhAMqB+6kp1iGX0y0nI4KUTnCpacJq09tRhkGTV10jpS7FBWk7ZILl8chwfhzGoRI4sMciHJksxo/7X41lqte9KE1eC5s3cR2i7qKZMTlvoNreECQ1N826TayG/qfGjlp1Zuyw8Q6dgxxYr+fOpLOv992lfK61Kzz9qUK0lLJXtRNZXssfbKRiMQk7BBTUDS1adR8QRyznSw8KfKf7PmB32yNf0dTU0ZPw18RKy3uVEp/1HYua1fp6TkY9eb8rCZUmPyB3GgtO0MzvhawMCjNroMwWUY2ll8ZOoKCh3g4hXw/YUScNn5+NqNLrZSVEncm6PMbUTnN6E/uQC8NlvzuRdM6tCrjJhOUKCvFCX/vwEZTwpwl91sxrn9+2OudzqaP7V760/WpQqFOKRXm+vW3TcHGQta5AKYNdvbMuqwjLUqMjRq/eSpWq9lcQGvquECC1bBBSe/TKt27bNsJa6CsAzK5MQ7+Yl38hOfH6jjZEeaH2We2LlFa2lfrT3dzPf0SZWebj6p1NMsXX5CV21zWYEI81P9Keh6mccNCFfc6jzSTBmGtVmHVEFbAHi0A/GNB/V6epWlx3Ts7annRtnGSsdUgjctjgk1o9KBVRwQAsqOiN5lpQVzp82KDD0vDqc3nrRGJCH5/YpsEfoZ5LyaLiy2IJnQ0ajTMEpWsujqFVOjrM32mj3XeWQKxti1wSIIvGnGfvQKhK2RO/4gy0O5vy+86D5TTJOcBLgfspTQ835fgLYfU0qLaFbA7Xqei8Kq3q/OHQhpYz9hUxwqQ5stjOr3BajdIEijbDEhKwIbtE83+/2jPnPHY5Bzazma00SmZJbE1MtCCdBB71/u7DhVlIbuqyRj6F4DbEnnYX6NpzbWmAysBCu3kG2Oc90hyfsVF9gzMx2wYBifEXTkQ+E2k+U6GkxrbzNI8QqsowWUKJ+qFCmfipQpnzyF8m7bS1cj1rR0jmgPyJ4QXrI1Az0NwII7YUC8ke/FrP79PtvF4AYvvg6nk8ZLxoeMSuClF2ECC3Lv0cDYpRhxBROv+bME8xasF2HRgnBLqep4ro5jC363naf4euIQpWNaD4HTlwJZUzfwmB8D0oBNgKqG0oUXXKJRMWan3S5DszOw5lrZMsgsBGLiwk2BDqq48c/38ZP63/ZS9/X7+OsH0yEOJRpPPofb0/B4ms5O4b79lFkHrtK588b/N/Oel4UKpp3MApua7xlnfuLxM7YvWRQuyD2dhEyMh6+fMW+KBwxdQUdLZ92YfAsWLdhLE8ZokMsRt2TLXL46LOg5DgMHMSIsVnbM5PoqI2G07DnHLjrg2Dtv1AfJ2UucJHRge5XsaaWkOc++btjztrTjMZnNZSqMcTymkySaod4LbvbedY8Puz1WO/LHURiHlwnCff8KPSe3YfTh+e77m93mVvPp1tPtb98DjKZ352mOes08Tw3ovnne4se0/ac7K7e/SutPdzKtQ3uidRHhJiCwOiFPNUK5hxhKBZewjUwwrs2USjtBDFPB8conCag/Y8Wq5m068AP04GREa30gosSjfTy8vtXDA0OnMsYkiPK1gwNteBqeAZFVK43jWnpALO6Hi4hymf2w/uUXCzq9wW1nL82fNutetkj3JPvm2Essr5p8QcW2T2q55b5aIwGzhXB7yr27RoEDXhR+aA5gI8QGv/wCHb8xKkvMwNqXX4iJHk/dOMYoFWh/xl/p9n6MDRqDZJuwI9cP6pygzi+YG13FGmfL7EeWRGZNS3a2evYd0laDcrY9FHzENG5F37a/3XmZl2Sxp9I1D6LZM/bXv1Lvz7cu2D7w1xj66kVZk4Nlg0Uk3MaolqHNMkia/OQNwdq+aLzM1xABfwkU8ZI3IRmXqfjOhaU0wudF7W08LW0Dg2ck+N1C8InIBJhBynP2t2xrzy4abI9tv9jassAS3K63CPqEvTrHy4Y21A1tLBu8exui/ewwPi6dtN3spI2neLig4qRNpTq94rzdxjFPK1k8ZzbsP7UVTDHWpq7XVac2RDsCScuQg+PxrtzxPdZdTu6EORz0ILrXxr11sYEHsTRQjeW4LCTn7ceQ805lcrYitIycn+XJeXclck7R8nlIWmTDbJLrX/OD1c5i4I17LLcLMs6V2Hd8YX3Pvku7oX7IL9iR79k578lFLduXwsbF93zjfHWx7xSNfo8dQSJVzeVaETjUObChbImdZBQC58ceJW6QpMcGxMbC3A1JAaPi3YXIHNkAyScPD2wkfzRkN0iszvRQHB8Zobte+j+b5uEyNzsqWWdUXGeUrYPdG7mSHL/ah9oqyV1J95CgZa67zCfyteF34W7z2XdMtQA/0d9GVR/2selz/4L9E1qFfwtmibdjNmSbLWwzXRXpBriR5wUbmQWvisjzHwO+XtJ1Wz7BGpf5Cm0DO9+ARL7V3K4hQ0s/NgfhW9RR8AxX5ANN1RtUnkj3GgpU2CMKF8iAmmEIBjCH4yE/P+hb0zCcoxrYzK0DDctP80zBfDEYz9GfjMInm8o/gJK9W/1TvXva4mGpzbei2Q0xD9nGJZAmKKIRoKKAE2hDfNvtDzrH3ePXTGF4D2Mb7fAlgJNF0nw1XcTX1IRZhkukdVzbEc40/0OMCv+uD9n+96Ay8aSrWpfDOYDT4nZgxd34URigQt3E4Iv6Fn7fYDzrluD+T9j21tbWBsGGLa3ZBd06gPFV2NBurzFIpJ7JXlhSAR/otv1DQXl8YDb5tg94hb8BG2rYrfHYmyeqQG7OjP5i5eZxeOhNXVTzsOMlxbk6wBKJfPpZhwUC6H8D2uLU4wtbtEzQi/c7Yx03yrqJbosDoNKrCPXa5f1MCshVPh/tr4lMVp4KMpNXb6iSEXYZG0WXmA3jGbJ4NFct5qRpC5MRJzxcO5nh5yjagj5QZdFmwcOAoLvij31Bk/xUF7yxTqLo8zWQnxfFPRejjNDQ+yZJ5m/4y7oEaauP+wGH0TTjwVOI5ATkfWlPKWjopZidl3m+q/XpVhzntaBFK4XHE3lHi4sqT5A65oXG6kAbdZP8UnVYiyBS/MFqaF2uIT/jHlD6ejLnFomeNwtvPBolBkZjlH51FkWiwuSO2EzgAUeceHcnl/X1vfWiJYYYxhrf7aP3Szp4CwqLAYpDAtREGgcPnBgASWeuZXsuB8pPFmRgYs++ZtsSaMkYeJ9Iqx87t94o5pbOD959raHmGtooAEExRgYcnPkw8v9FZmaAYVCCHVAZuWF2EViPE7IbF1D6V1ZSTxtukDKsfnLmGb/zk+t67cBzI+haTdIUxgcC4uMwaJ5EEwyz614FQKhtN85tkPgUEJTWbb1hNUHflEyNFR2FK5rmqIFC/Vc2LUH0I7cbVR6JEOgXAY5DF+rJ4J1K9bU3g8Hp5nZzm+1ubbOzQNKBN8FVK6K9RVLFPbYlXoprAvYwqUns4Uta40UUK3keF8jqvFN0xpb/KdWGZdVTUcxeTOeK9jKCVa5GzC6JLj9bF4GQAvtvWtssvna3AdX4d1NmVV95xkTCdYRlHGovmkC+2L9mtZ1nLzqtV61nTufb7V1n95vDlvPts3bLaT9rHWwdtl88O9jerhXKM2qM0LYIvm1mUmFR3HtV1KnRBBMYygevhATtHUoJcxsIs0/RJIhqaQmN+a5iieWj2mfzqwgW7x5TzLG8vE7Uom55BRDJndTFxKXbPYYqRYrKr/neV7g2MutCIYuWhvpVsjosKyNfSElEXN0qkb+p5HK5mxcTGKvb5WgbeFO2moyUbMUBmrJVvjo/Z8huSanDE718SPy1dTxkhCEWhRxdGiPy5YQCAd0I38UWLWLVNTxaXAoo9OLpzjfPX9hse/g8Rs0S+txXfGgWFlMBBj4oPwWEf0FGKKzWofdEgPDvEsas4KAkIWSqMr1DPnQeu64mEkVaWgHvYnIaKhkZunG3tUM9AWW48bJIQ8Kn4FOZTmUcmdEfEae/8rwoUlumCHKLwCpYeLGR0hMatclCYD37Y28sozIsq2jTEAs4BiyZinqwKJwqwYWWimLKLtEEwjmeYilAu1iZc5FwkOtleUyjr4DDKZO+FZTUNMsrka0RJqt8GSAIo/y3BUu4hNRWIp7Whhy4+kOt7LI1tUQ/KqiZG952DkE7uTdbq6NAmwnlE2FFcJbAwkdxQb4bK4xt5ZFWEVC5vIrPCssv/6qM3WQj762r3crnLFjiLATxzWWJr6QXQkgCVbjKSmyoKJJN2JmEXJ41rZjyRczNLIUmIzQ7f4ds4Xttv05f1re3dnazUyfYE+6MPGL0O7b9/OmL3Wr+WXSuxOlGi9KvlTjIsQKgt5QfpcAUg/3AUPA69riRc9DIdtFzqLpc0N5YOVGh5PmYOWyXPNDbT/V3T/m7Lf3djqXctihXnYGLgeZ1BKF8YP/TA2R2LaTkpx2PhY47nJ7OnQtipSSmDU2248ZKyqtR4tvBHenyMvYSi6NL0JH4/l0OVgGipLwWa4Iah7HBQQDq+e8ispJSWol/Dh/Rsa9hUZTzFQEnw4CseOXo07fdFLe47aZbeDFS5ZZBm6zdhXk9iXTZOxfNQJandH6hcaixwXYaZYtNtQtlMTTjr9iBV9kOIOXwhBAY84NFt3nRF1vkrMtSwTRE8yn5/7XC32ThYo+pFN7H+Hw5lQhE8EMbxYiwIwMvjVqCDOo69boOpREd333HQOR5wMr5GIkMxSjToxrSN48dklWnKhjSi4pDsoVN2NzSL4Q7WiAC/9Gx4C/BgkQAMHkUhfDP72ErISffzq74J9tjK70jwQnTvsRLLiwKWxOECUzaxI6ov8F2cxiytpdK0Ko9xE0DhmBrlo9sK9+uEq9k7dIJSkewnFhs02UKcGLuxEsKI9iXiDj32f+wHAbtbE8AqOIVM4TzlPGlTE9tMBM3cSvtMML0eOTNwuhegJxJ84X+NmeFtCBtFnOxl4QSLk/UkXFhEKLgfpzpNay7L4kQUiLKMamCNgva5cNevsXjo7iJaHyfPX/27OmzR7aPPS8Q1m34EY1+/z2ue8TOq1eF9lVbfV69pGLBgB87uG+KOregnWgheBn94rNQUN5YYd/gCvuerzTHadgxRbABUXUfeBvy4tVGnc4waniqiTpfK1tC+rGaAPmiuoy4E2+m5WmyuUEFXCpOgOmvEr0vLlDylmgwIuBI2GKN4M0NMyxzwwgVLPWAPzbGRjX96WE2p72TX34d9jqtw18zgTaFjVSJtSkOYLFrq5VXSBo3QP17ZMyKrFstZAVj1psw+UaEymkU3t3rIbMUJ2FGzFZcLAXxIkUm6wJD1WcJCHHj+2BMA7YMM4/7R5I+h6KcMYzSFj4y/qNzh1OOp1IwD1PnrjQOgjNBzPQ3m3M1T/34ju2qH19/XX0/yo5lDGijazPFWs58LyRJVa8pIy36XtLjJ4+5vaReaxk+/w2mvOqwXK0x2oWIXDIofNxb19eGI91HLaQQDBVhZ5Ff5/Pe2GBtNxh70yn1jFzfsLSCQpssPjTpCnxJwRUDo/DhRqp6Shve3SMstpKevLulroEUTSo30KNs9vhQFLGiyqcNMRPEhYhb1Z9tba2wDyOipf2PH/yqi6H97W9EogpN9dornt88CdGUjNOdnspjCY/DtrukTVNeMp4rX6HitcvchcR1EnTIK4bL2dF/skvvltwjCVnFFaroDaxjgweuABsfaTrik68QSoYkvgb/fLcfbxuH6AWTdOGTONb3rjD8VdheZV8CYAUKDUcgtbhXHh6Bah74gRuB0sqTcq3OLT6nt5AvWTU4Mm6DMDNfCOamBkBfcDIXMXQwmrlTfLOIYAS1zsmrWvFAStf+xzL63/kv/dOjgPW8seffeD0vXkwp2l0tils0q9LHZbT5qA0KH1wxEV63kJKyMVKdxIlaqi0sCbatVKTy8ktwhU+WT5CMbzIK1eKyUdvgkaTP4S2r/m9y+iunPN9eKjm1CpaetsO+u/aCVnBfT7aBWe0sOT71ubx0sEUrF91tXFWGWBUB1sQD8L/1Hz5TlsbA8yYxpf+D6rmT3OK4dfawt16L0nKZx9ipinn627sDfQ/jkiPKkZrmgsTEj3TnA2yR0yn2ti4gWPJAyk4Y4CjltzyrTembjDHR8XWFPJV6LTdUa7fzkNQkpCjRShm186PkCzw3TNn5ghFjHgC2n0uLoBUI6Xajv/KSm0E4Da9CthmCgDjz/+V9zTZ5zNgensfbhMJ76hy9PBq/8/1ftzM4ftvqDzq/dAftk8MOIXmLkvkX0kg+aTDPWKDLp7M57kC5Q4J7NARrPib8R2Xp5C0VpDaAtbSYXE5Bu5pwyeX/v+wG48viPAXjdHglKSQIgC2/l/iUId+1yZSfSq5dJ8k83tvcvPKT68WoCVO1mbao/TnZjLyp58ZevAkbM7S8OQlvA7TQ64WcWz+A97HjzibPd/VUDO7cz7QIb5paq5EHfLRi22muBhnCzRMoa5emZ1PH3o5bc9/KKUWCBa78Z2s0RfwDhQLUzmIvclpXeGocNfqDIdHz5k5zy7j6FnpLmXX3JZBDgSp5aRFHRqM0Zbasaru0KOaeb9lQk17EAA52RFgRYnzAEYdNfoMC5icsnybKDNz3MJuFrO+88qM4YVn+wFvnWRnp7+bEv8JMSrZX8l4ZniJ5r36+5XzrOpct59XFH893PzbW8umJsnN6xK/SOd++kAdBdGQoBp/uo4I0ktn8cGpdU3UdF0O0yJy/XvgTYNRAHfgXnTmRubuPaw3zaMrzBgYfNwG+SuF9a7+czUJaUHRVmsqTsiIo3F/qfDFviBGXJkS+Lb7eW+yvCvWZ/HXjZOFO+YzUcUfClikjuEAtx7bTml6FsNldzxi/fq7RxEK2ieO0pMDSbl7UPD78MBPnsrI1YqVVk+ETKkUyHZOnYl8dzOB9g/d6mvfHfcXknaQmYV6hOKS6X5JS8Ej12sTUoYeSDG9KbgD63pDl3x8xD9Nw2Dk+5KmYhm+7B8MhtkKY7OI5l+lUJE2x5Hxc80WJceTPVcbk0z7/3QtDLKovFv0Tq4naw1g0MI+3a2lC5VrNuDXTbConKRqfzQ31r2yOhBJTtijnOJQXWTiYs2uByDoNp/74nh3c4z09jOgwOzbnNewSt+49bjhr2t+Ac+w73kXD1tK/s3umsTcLirEMP826xOX66b3KvkRIOAv8pXOyCD5tVlT9avOSbS43M5kCn2VuMjCrYNs6rBJ8P14XWhOXT4o5Qu5GNwHwLfPSv6vxm6xacX4WobboHuViu8KtJZckTCRFwjStKXevZavmbyLJQa6JN0PKWXdF15IgnAnR8U/efRUYvDBeitWczEEKIQDyYoO4EgR1MUKcgnDltSlLKlM5rDDiG/GS4lAKC89dn3LVu6A2RFX6KCo0kzsuKdpT9GqMwVQY1L080RVKaRmVoDyXsKijZ3Pjr9RZVnnnH2ZaBzFi01ihFVpAopLp+IavW4POu9avw7PeW6PNokLVeqExhByVmrev5q+Hgf3qimWus8mTuoPntzN32iy7P4YnugboZVd86ZiCss0rNcn2vLjpLquXzSeUtmCs2GCTsemY2qzSf0Yj5zekQ0e024TFFPuJc+/PRqHbRBcNComwZDdzWf36rqTi9K4nOxEfU7CFdvFTEMDQyvTc7HriqbFXUHRzC1LIaVLbnbkYCKBumctQnMmOlpKbF4x5LoAltiUTbIHFhSDSjbJCfzsL5vrVi5RTu083DcJg+Rdvwg9yqq44/XEIaKlR4SMXT1Zm04quhfzupLSpZcSvXcNHKaIBQMEtfITf8zV+5R7d1iau16tAoryqqiiIRVkMb6VWizNYdo+MnJkTsk+dFqMQx88vD5LQS7C3zK6Wm2Leg8xcmwtJGdcOR+kpVb72CxaUaCOzrk4AE5E/QaIPVtsxjJo6D9c/6Ny5HJzWPb5wtRdofTn0Lt3FNCni9yWr7/MutT97ma22xGhvCdWdZAWr61xH5kVRXuVqtfmatN4uaa5JIRIfHjDJ6Nd1QOuaWAyDHNP9il4kcr81MRCOpzp2OD9eRF66ZVyigcfUWvKlLHrLcjJUtVNCNF6JQ4IO5eaqdUBQiJg2RCpS95pXTUoZenjQqFVfAvmlnDHaxpTvL9c+JkjOMQGMRFo3+45XxaA+MAYs8VIabLQTaUsE0J/4M0yfAi2Ec6FExM0jF/Qodwoj0OEMwoP+oIf3aeiJzbjvyDKsldo5TSJJbHg5RZ16atzaoQxGK0D9B7x/FXke77cBUvxjE1UcoYIbFOGI7cY2Ug6K2L2YsvOTny4I9oQdnrZOuw6wBUyBi78P2FwtFXPm0BuR4U81Ek88fr62HU5hvl/DgAJdaJNqJrIgbsUu0iQcLu3rZge+sMpJVgBumCtMS12GlwrGmAIHr30fYw7uLG9O8O5eG1mr3N2po4SJ3jFQCcQyK5RKvTt3NgcuoMmjjZrJOStpLdS/vBCu4VQWqiJymzT2CARrrFWbPj+mG0R87AU7JSOG9jVEtpowq2KVSZmuBIxucBN+8CQUPFFZeCVMNUfVWeTbbnQ98pLrkFICve4MrHe+HoSTe+kjyV3pKhLf8Uyo289s9flBmLWYrDh73HzG8zFqhTGPSYK3k+MVsknkClO3Lu9Lm7m4qkVjYmguRwy980YimhJmUyR7wXFnajbVmMXoM5/FmPC7Njye6i9TlE7OIXdZoc5PnjdvTTEbfpqCfyXJD5MUmatYghZYO6/9whmMA0VrJJLDHwblp3rB9QdSDHSsQxfv4/IWoBrB1avRS4t3oPxWbSSvguEIQwCPyGE1F/MvcSP7JlqxXjK8jg9W1j4Iis4LXYjDqCC6iVuJkGlqG95icXPi2Pq+gKKuHtTLq8hHVfm1iuSVAZDl+qcCIk438MYohsdoV5fvbK6ZDDARIFLsVsg6hUBCm4dB7OXGwl/XG5my+sh5Eb14fuxrkUxYVnK1Z48HP2sNFEn/EQ8R25dwaQUOQmT3+Ubz2NBaKPhII8p9kiI6b950HZ6bTjsVaXuh45lk5GFT4qnyhckmylMA5Uj/c5CvoIJ+2as0D0vno9K8qELa8AsLKUum7GPG3FZ8MTNNA+3sa0M5w5YFJ6RquVZaoxBP4dgsIx/5HShC5EMpYEx7EuN7IOtOgNv4CSYK6/Vbzs7W7gv2wbtHKzTa+fX9ssuT9mVfD0Smcv3LwAvcIMlVOHVROKH7jNWuagJrkwoolKyKW1HqDBO6mvothLFsBNUKNuo3J/0Bh5p7bQKXRdonR6dng07vuHXUYbnhnUb+zS+zqRWPp4tR+kkotKaDxxCw/+2mz082rsek8Px55nWCbzWUp5+bwonkTwg7efrOFtOMHEXnHkQVbr0Y8pgVtMSsRrXFyyAPv3qnElqIegPa0jTKVIcpcEMHgYbkRiu+9N7KKVaymBW1WcVULXhgyVjmxJGGdOl6/tZC+WQN2Ja6BQZtOzwdNTpPtFm+rVa2JQMsice1286zhlTdLVvFi4GDqGBb1cGWejEA3COtq9QTK2ksZSJFrFp1p4nvYO+E16U1JSPXKi5GoDUY9Yr2aqV8I8umMe8e+ld+cgqEJyMvInk3Or9HE5hNOCO9gomErGxHlOTZhOvnC1CUt59fQE1My+HE11M8mu6A3MD0b9sXuuWI1VFzBMmgTnD+h30LPxsNgyKV8XXJvbsmo011LQsLzg+cmlmxETF/Wksf5gbWYhco8ZTknNLZ/zDPzXvRfGNRc6bLdvHM4qniaarjIIqdV41lTHGpFyqzQkXvLGs1R65kKpXXXvEYBn5gJyuz5NEhyU068qBV2CpkPFF+C8Eqlfxylt3HzhosMUfoVT8hN4x+S6KSC9LFnzUrdSdpcbw4gwQCo3hWTkzL6zJEAfhUNEirzTJ3N1I1CgBKy6QBAnpXhGlRY/AkDGRAZWWHHD70fXlfTmBaytgps0D1DTCtspjjKVeok2j9OD90uZULLcrJ+Di81UJd7+Fxjo6cyWTw5s3ebLYXx/+QUagfLYvmEDTka/aMF1i2MHJi6oYkkFIPrTCgCj7BV0V6MyTPHCWvz6TdQhBx+pYOk68ZJ8nVLweU323tBaauyar7qixe68zDwbIcF1elDHV+P/lj96Mtrrkam5bFNYlDDrN4kaAaK+y72WtdM8utDIqkM8DwcMzXwz5v3CyTWZKlyxGfzJKsshy1ns8XIwxYy1Xje4YuDZSFJGTMQ9yRbTHOO2eRz5S/AN0OAiObwlIAE+sIw3PtFHTYGnMI82oKHM1wvP2Moe3WuN+V2udsUXUlL1dVjWomCpUQufda/Gp6CIAHMuKigz01+WSqpOnMdeJjpf5I0oppgeZ7Yizeglpmlcx15TkDkH4GiZtsBDR5T/yemoLUfyNHwXfatFM219FZgL4OhI8e8ujGYy5bBD7AZrvOBLGnWjztHjP3Eh1y21syeUWsuY2qCTvLmGwuVnIDqLTV7XWPXw+hB/u0mv83+t/gsPNzt90Zdg/31/KiJRbgV04fDs8GbShStm2sh+uNRs0u4PA/dMft/md5LF7bQzf60L53g3yTOsmk7tB/dHonzqB31h8wjgwmEMV6nb+fdXudQ6MeszT5qzedhrf/IWN0vqczEkDkSGqMYcJ85ziE1Uy3yFi83O59Hs652G0uyv3iuaaFHMgjN/ZYlqhSHt9g9dx20bA0RlpJ0TgXAQa7AGgaZ+wFk2FEYx+KG66bIxflWFQLaDz/WZPHGxXH8rmDV1/klBHK6U89D/YjYD5hMImlOkrMx2YZpNQHj9jWeMVNjiVtb0M3srmXbcm9DCP+Nd/uDyDz/+II0czhzLImdXfB0D9auyt2wbTv1YyUqi7fX9TvJv9LHndzoe+TWq6QLm+XmDqz5UvMnfmiSyyBdpteQR9LrVdWk6QCkzNLFgMwbWgpCFI4zBFdmI3wEkJKK22rSL+1T4FmTMvtajgVxoGw/BmBKofDbHNjMEPcETqHF4xjhwfS0XjZ+lrdgqXGusmG99h5jhXC/soucHg4NzqnlHPYaDTLma/+ZEQgfCzpUEvWjCYlvg4DLy8hWpEC2yTHihRtvLs5j5qha9DdhO72oZwmUhCCUs2mbWQ6I7aR5gqiKT42hbHIv7iKkfcxZjpha9F1Rn2hiaQiiPwthXd7//Nhy2R+6Z7e7MqK2ZAAfy4Pax57icpNyBzxxyt35k/vGUEoXyUPOfTlzxlr8EFunvofPH7f6hPJgAuKPP+2ufNsF4t9tLSTOZDcuZsDLOEdwK4rgOKocvZ8qT/XI6oBIZbjwik16DfEypA/Yzo5yufCAacmIC321qUMcFEyAm0D5OSMweXID8ghkVZoUSwfz4iQ8+f6MV5YygM9ZYSR/IZXyUI7IlaFnIJpEJKikzMyAQlaUh0riGzn2ZPQcBIGKDIWnT+GzUkE7GniBN+xQI7Iczt5VE0HQOfhPtlY8W8yRNBxwyFQj71Xgio+yXiBjzzgN1OmF1MRzJTmsyUfKM3nL9N1IMjhtZr4T7D/ySdj3SyzbJZbZGQp6V8vklolvaVWl7PU6CJJSRdUn2mwq61Ljog8azCZLsWqOFoKk4N72JTsa4kX6MqM2qk9wbbuKWLNhf0AxOt6WtVi1k80fBsgzlW1C23RciaYNMeXeGhzrJ2cS1/iAX1kM+T3Z3iBMjoFx8RVYXhaQbRzVhKqcuzV6MxtbOmMeLm8M7Lg4ztTMYYlaaKJZhj/Ph0uYrwws+qxw6Q5GeEh3aCxPJzj9ymd7rHFdSFZN/tQgJJH0F8qKF5vxA6SMrplZfC18YwrCKIMD61tc405V3jRofRDWUQ0e958igOtXWDCiouLLIPAVpoC6IDfKlDrvmKdX7r9QZ/V+523nfaAbbNXvZMjFt/HTUw0PYKdBCbWD8b+HHYx9u5Np9eRt8Meo7CdnY/1BjvsnZyys36nx86ptxcvWWlD/EzM45p5e/IapFzZTvY8n2BhNHR+Gt47DoO/L7zoPodXhf1ciGfBoTwry+DaT11nNDZu1eFiuRQwpN8kCG9LWGAaq5HATgzKzg91eycovjjvMEHozpVXxKkA6EWT6wvxcJGMcxqHndE6cqgMIeSsvpJdr42nnhsgExEsYV93n+ZEKwuTtUlfaQqwT0BO9XEZyTSKrcGcrxYIeY6Q52rh5eVUuGgzBCZctlmAy3Zkw470Wzgqkfo0g9IhrMdBx7QpPbMGcj6iF0vFz5U7IulJ49vnIp06LJcBsk7cZKJw2m7F3WDODw0IETxT2p1MhjypJcZLoPhTl1/5684N8HiexTu6+EMIE2sxhg80KL9bhqY/4nI3Uh6lQQReMMHQP34Y6sdwJEJ8i06dSIkFSnYntnMfpKpyedX2mVNZ7kAJdraNV29oH7TDIRRhoAf2yrMd+rFQvVSx9zl38Bj+7AQ3qPsaEQ6n4nIVHt1AILTWnJ4HewJutSIWRR83WmGDiRfJkBZ7oItDKGQck8XJvdbmNG2m8pOR5m3ivAcYlW5ZUUQiOS2EqfamXur1/0SBn8fJD0Gr8qbhXBwuQOxKBlI0K89zs/I5eMomx21uRZ+2Bu03Sifg+DXdsLncgXyTdkCsol2acr7YRXlxLFE77A2V4BdeSXWx1nNvD+miDE72R+5dL7yN7fkVeNCU505Oguk9AGHYPENw1nNpB3gPpTfZY9S5dernOgPd/J7NvWjmJzE/7IfQGJd2Nt91B2+ImDw8NRg32RkweF4fmsFRr1M8BF1uqbsf1XYjRsCcqcz8mL66StgzjF9D7ixf7uMrLbPg+HECrZmYImtyGNtEWinOjktlWUMcVae7nm4VlBACa78zYINe67jfag+6J8es2z9526K/3nZ+7rxleAsHOztunxwddQeDzuFLhjXenrR/Gg66R52TswFhir/unbxrn5wdDxTSXqKDFfPO4dxrHXEn7jwpOOeRRx++afEadRyDPuhJXAwE/9PXXelKfBXto2t5WgcYxqEaPtk/5HK4TeLmAJm6smbyMBky+qlv51sXTRy5XiYfAYBXj1MbZsV2OF3MAsxvCBpfB4Qvw/LIv5Lf8WNW1k5mcy2mFkpOOb3FTTJT++MmXt5yzq+5vgAOGXi3WYE9FfgmEYUu5wZlNZmLBATnYTTBQ60XP9jSAqewxwQaEVAcCY57GnTifG18UVAC2sSvMu7vhjl+DDvAAWqpF+lhhvS8xU3F61ARk5Sv8Py0z81kfAousMkMwrK+PkE55mbs+4RD2Hfxa53gp3dQ0gkGpNM9yWBz8j4+QnDPWhH5bUb7vGVOcWYB3D9wb6zzvhVtYrtaWGhe37AdKuI5ipAf8cBNcqsg36oR8sea3pcJ8IIP+cyMhXsW+WMevWdRCF40IyA5A5XxcfmupHYVcW46Rk/Q1B/jfSQc0pD2mn3UoDL7zefZK9YSvPijJPWrffPgtejbgXflB4PIDWKXt/C4TUaDQCrj3bJN6Hn5JpTdHC4veR7K5XYGaJtg+Ynt8KMElLF3Zqg4uUOSFaoYwOsB88QrrYwzciueuftTlwePmiDuchIceoRI0qzNNbIm9ABFPZQiGy/PklxTFGjyL8M53quFSTFIwLN8TNnp9u7Tp6mtNpke+UEOaDIdgl5BAI/c5Jp7herbO1sb6Qv3rr69kW1QVNROyz3d0hvjZ/dls0+IuuTXA5lvz25RYDIhnwKdyWI46BydstpoNKTcEENMzJc2TUgGagTwIiW3ZuLA945oXvZDrv5Lo1I+j3e+ntSgonDkWRkHHt7l1z3AJq1dzaYf7lVuQ0B1elHbVkMHLm9lE+9uY0EgGUCdYHIa0jTxWuQKgpdzfNloYqUM1HCOQCXqwg8H4oR76VGUpzsGrmXASL2eQrDLRqmmd7cDa+wjbKy/QddYTWUuTqTxCYRe+NtZORvyi3Q4gCU07O+Lpags9xiPIXLfpjTRiq4WqKPgFPHkliD4SkQrP6yxPo3hC5IHre8dJbPuJ/cgTrzxJxM8ooC5OwbX0SJVSy47UfQ2RGOeRttyYdQUHprjy+Y0vKqpasuGxKk4MxwOjTmwpTruIgl5KD78XoCCi6lW9jY30yv8xKhraISY0JFSaC2YuNGEXBta56uNlbcu0q3XjJc92OpimSpGt1atQc9eYUxGK+slBG4knNZUbgIqJwUUWk0LsLJEwFp9R94UKuLc8qUp+l4BLA6BOwJ1xI9FHNzTrS1zQzHS4HM85TULmNIBbarGydkUr/zAbOU80qm4lOKaazyiIZn4vC7z6py7zr+2nG+di6/fN2FTTTNQv8fs9w172I0xk1oidEvJwunTDfvysUUILRmIRjiCuMdKIivtvElxqR1dfyoGMWW6aKUoHRPItxI61USUgy6JXWtXy9vPn/PMDY17K4tI9sWW2qiNoLWU/ColMk/bX+KAlGiyOCAtPlXO4lZwqBYZ7POg+YbwaaBzGdsZ6BnjD5IKJ/6EMuB5IOwylxlLC1cWpbjCuD3Y9Xae5QPu19Ddh6m1DF4J7yj7k/ZuMhKuWvnGEOu8+bU38yJ3OoxCdB4udf0qcGUZKB09P5pqK03BzBwjSaQqkS7NYZzk49+MMXOJDnr9qJ3fADuvJMxsv7D0RmD7XCji6GEJ+ZFkeWcGB06JwL5yt7MO2Ll0VgtYqZd6Hb3U6+s5L/VCq3FWya/9eG89n+xsIE1BqpgyDz4VWMWLLytk7Zv8dIfp1WZkPD5t9fvvTnqH3CGOeF3fYO03nfZPw9OTt932r/Dh5NWrl0yA0P3v7NVJL+MpZ623AyjQO3nbYedAuejs51lkLljr8JAddY4ONAe+JfvAKs71wtRK+HD/r8CaVQHNuObtoduijOViFuqBtm/kNWs1738OHy4D/xl4MYE3tHxtxClHFa79ojArXUYUQrxURgriBWRkU8Znxt/LYMH9VJdJi8hYIyaLcCykBWRklCrAZ0FrRI8G0flFWkRE4qQw+HJPC2ixDrxAiqEM7iwGzQqjFEUW/FzyviY25srQiQKtDOlS+Z5K56HW0xW8hhVwporMOeNXjHuJ7ZOH1v8YjgoMn9yLTT7YQy9x/WmcqqcUpE+aLnGCtEgavo9MwPLeOM5hv1ujXCQTTTfSm9QKwsG1OEBZxxAljED8fqd91usOfr0AsfI3bhv8DTDDkcAuI5B+FgE/OK5OLQio67ZA/J6nEZXldg5eOc3VYD06Ihq4yGUO1BErHcorjW0RxP5VAH+Q1z7BnSwd7qrjsZuKS5JSq/CBjnSG2wakxxGUBwvIa4VEZIEIOtAxrIrocQWgWrh3/Q/eLZr7DF14bS56WCnrtWVzKsD/jylJIf5dQKO3OfEowCS9J2kP9oRHTcHajB9upzUphtDEd7QY9Rf2VXiKd9L08U6a1CSpMvxm4aaiswE9fb1kpaMMgiIUDLOFd5lk4XPJn+m/8xCNGuK8olFLnmG09YWjS99seQgI9EQlKA1v41bqLEjzlsYq6p7FyYT7IGq1l/gDtAj6Ubg0qNMzdTMOSV+W0+RjkcN5Fb0mna2MOjOvqM7MVCiCSUTu3TDi7llhS89+SdH6LFXRFdjfe6TMWENF0mTVcsQ8lkOb+NSHWRd+N/kxcm9JDm7QYqauyzFkupCZSupSc5x3aMrJbap55UV/M05QagNUdJhOqfDk/adMamboVudnpVnQHZq5qTB8lFmFL4fUOq0ceUomXoxRvIYFhH0d6v45o/NlxyDyfuWC2eHSsGVykm5wGSoDtc395citS47aPkySwhDYMiyIvuDJRSrfVCJqg/Hc5AzzxmsFUrGykVXcNeiSB1VFCWlpRXhZGmsrKUB1foVh5+o22BjbmzQrd77vJa2p78bLMnKYaQyLdwiRStMEVe3A7dL4YX4abCl+aDwy6xDmxFgvyQKwXh1VPX7UrRhTtrNweUOzrcd47SYT1Vk8vvYmi+kqsyjv4bT0LZrrEyayE8zd5LrwiLQ1JWk0p3NAwgwqThYjmPTeD0xiMq/lti+ZO7swo6BIow0tFCAK2fdQHI7QoJxyLzXsBa8Eu18KZML5S4l5j3q7lAErhON1nHUzwTbjvyrP3dn8s83c2oSc6/351BfzBv+NyMUUzfOTTMXT40RG2shHJJ2d5PLM5mkgRTzqARnLqhipmiltnJmBFqefUcQk854vn0s+AYUzSXd1RPOSCc3O3F9Yqgzw8KR6D5RGVMGZJ++ozBmt9TVy5AbuFYXONvGSlBklqW+mUNP7CKoZc89vQn8C0gbd9cvvv8yJ/sXYpv4JcQ5A8NBpq4UX45xJQKtT+Qd2skgccfeNukejIAW4qFjHJnjq7rjJ/c5LYgr0eAIKaC1vKi+i8l6XF+VCgehngU032/FMkKmhJG3nMruWmYwRdAVDb6FKbbSsvc4PcNhUCeebRyAYAhlmFWU6hkxqJ13+WhzMo67jrBjOw6/lVBdOZWwighMBAXNxinrQCbCY05ItZTvnmDaLljC9KRucQ8tTcOP0YiBdbdA9Fjm925FHHzQUUyipkroNGTwzQYX2n5mXuAV59H4LR3rOyn0xNrOQNBimhcSAzWIrHnPP5Kbc53gzywhmMuQXrTOR+IEmrE+v3nh3IP7akJkh7PzB8rq4G1ziWaSrYDV12kRP/8ntQTUjGPvznAQ3zohwoi1Kxqcm0nIw3HJXPLEAlf/gccPloIqOX9kWhNXoJ3phdMlK7frhKMlQhNm8skT/5Rf/5sxX1rRstpRsvc7RyaDDWq87xwNW7+x0YM4HZ8fH4uzFrw1ZuSShzP/p2Mx0bIWJgIoz/eTA0Z9cyfocCdYKOj1I8ztYkxMVp2rLgZK3jHFQYu1aB4yZ6P7tOdjWMDmG8JHSUhXWB21TEKFrhsdGPzqc8i7bceuM9bRAW11JrdUi9uRz/rqNYik/25K5MkhzuFlzxqHQlM/lUn6kNyfXr3SNl2ozrx+Ii1jGKAZROCrsUZsenox1eK2Cpkuuy8onYyoAoZ0Me7ale1WMUpZrwkTxvLJT9TYmbSZY5duYRCPVLwWKl10ItIaK38EC5CX9FgIUE5pc3D9Y+FOM2lBnpMz6xkoR1wSBJnByKW490rJ9lK4j+ZSvJ/nguioIAyzI/GKJCdx5UXjk6lGmMXw+ZvFDOBZxs/pdS2/hlU1d4okUUB5C+WNNBMjySEU7dKqB5XjsevzOT67rNZzWPVaz335OnZLhNSkBNFvzOYgx1DUBUcV9PbcpqZpfi+caRfuKTPylwRURYPbTf6pDkasumtbqLjF1ykdo3FrF9hTmrag4T1csGhTpiuUvGEgNkWMPb1XdJQ7FM1nmkzhTYgCxNlPI1QONc32VrZX2ifqVuoONik3uefqDmW/0O5jkgCzhT0YLPDSfS7TGCazlNYTfvFo13avHTzSWm2vME4pLMZVtwkgjigsBqE4SsyxiDWAoHTrZbLNzgS/NueB2RiBwfgCF7j61OKKXNmfOjRieaIy6kgKF7f4xxz5W74o26VZPlO3J5ygpe7RbhqKQXzQkZ2zVy4WyD0ch1OV3Ckl6UC9KqSYttTLhyCe72ghmPldddTD6bKj+rQbMEjdf9lQkmArFlhRZ8pmH8Gvo5LNkvAHmn9MPKs2ZuldQvynxpRTxtBfZWypfLr+MsOzJR8hJk4MxLm3ic6SwvBGbyqTDXw7h0RJV9qlAeyVYK/i0/DC8Ndr2z5vtghjiP1PufdQM2dBiEYBRgVwhR3nl3FK5ZOXP8o3Tqpcd4Cte/JLXUKYSn/W7IVf/USZSY7+Xi4PZ1leXCvmQsLHPKxVZtlFs5VF76GfeN/UvFBXxeE5dzDE16Dq/XGWbtHLKFfbs/+/5ZMHWZb3bYO00nE67QeJFN8Si8q41THeW8dPl06KR9fv/AWdEIfniJwEA"
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

Start-Service -Name $svcName

$pairFile = Join-Path $installDir "pairing.txt"
$deadline = [DateTime]::UtcNow.AddSeconds(12)
while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path $pairFile)) {
    Start-Sleep -Milliseconds 400
}

Write-Host "`n[INSTALLED] Service $svcName is RUNNING." -ForegroundColor Green
if (Test-Path $pairFile) {
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
    Get-Content $pairFile -Encoding UTF8 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
}
