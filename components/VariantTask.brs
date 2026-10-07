' Baixa a master e devolve a URL absoluta da 1a variante (media playlist).
' result = URL, ou "ERROR: ..." em caso de falha.
sub init()
    m.top.functionName = "run"
end sub

sub run()
    url = m.top.url
    req = CreateObject("roUrlTransfer")
    req.SetUrl(url)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    req.EnableEncodings(true)
    body = req.GetToString()
    if Left(body, 7) <> "#EXTM3U" then
        m.top.result = "ERROR: master invalida"
        return
    end if
    if Instr(1, body, "#EXT-X-STREAM-INF") = 0 then
        m.top.result = url
        return
    end if
    for each ln in body.Split(chr(10))
        t = ln.Trim()
        if t <> "" and Left(t, 1) <> "#" then
            m.top.result = absUrl(url, t)
            return
        end if
    end for
    m.top.result = "ERROR: sem variante"
end sub

function absUrl(base as string, v as string) as string
    if Left(v, 4) = "http" then return v
    path = base
    q = Instr(1, base, "?")
    if q > 0 then path = Left(base, q - 1)
    if Left(v, 1) = "/" then
        s = Instr(9, path, "/")
        if s > 0 then return Left(path, s - 1) + v
        return path + v
    end if
    for i = Len(path) to 1 step -1
        if Mid(path, i, 1) = "/" then return Left(path, i) + v
    end for
    return v
end function
