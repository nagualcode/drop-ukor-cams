' Baixa o .m3u8 (e a primeira variante) e imprime no console (telnet IP 8085)
sub init()
    m.top.functionName = "probe"
end sub

sub probe()
    url = m.top.url
    body = fetchText(url, "MASTER/PLAYLIST")
    if body = "" then return
    if Instr(1, body, "#EXT-X-STREAM-INF") > 0 then
        lines = body.Split(chr(10))
        for each ln in lines
            t = ln.Trim()
            if t <> "" and Left(t, 1) <> "#" then
                fetchText(absUrl(url, t), "VARIANT")
                exit for
            end if
        end for
    end if
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

function fetchText(url as string, label as string) as string
    req = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    req.SetMessagePort(port)
    req.SetUrl(url)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    req.EnableEncodings(true)
    req.RetainBodyOnError(true)
    print "[PROBE " + label + "] GET " + url
    if not req.AsyncGetToString() then
        print "[PROBE " + label + "] nao foi possivel iniciar request"
        return ""
    end if
    msg = wait(10000, port)
    if type(msg) <> "roUrlEvent" then
        print "[PROBE " + label + "] TIMEOUT"
        return ""
    end if
    ct = "?"
    h = msg.GetResponseHeaders()
    if h <> invalid and h["content-type"] <> invalid then ct = h["content-type"]
    print "[PROBE " + label + "] http=" + msg.GetResponseCode().ToStr() + " content-type=" + ct + " reason=" + msg.GetFailureReason()
    body = msg.GetString()
    lines = body.Split(chr(10))
    n = lines.Count()
    if n > 40 then n = 40
    for i = 0 to n - 1
        print "[PROBE " + label + "] " + lines[i].Trim()
    end for
    return body
end function
