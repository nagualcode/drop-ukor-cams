' Diagnostico: baixa .m3u8, variante e o 1o segmento TS; imprime no console (telnet IP 8085)
sub init()
    m.top.functionName = "probe"
end sub

sub probe()
    url = m.top.url
    body = fetchText(url, "MASTER/PLAYLIST")
    if body = "" then return

    ' faixa de audio alternativa anunciada pelo Worker?
    audUrl = ""
    for each ln in body.Split(chr(10))
        if Left(ln.Trim(), 12) = "#EXT-X-MEDIA" then
            k = Instr(1, ln, "URI=" + chr(34))
            if k > 0 then
                rest = Mid(ln, k + 5)
                e = Instr(1, rest, chr(34))
                if e > 1 then audUrl = Left(rest, e - 1)
            end if
        end if
    end for

    vurl = url
    vbody = body
    if Instr(1, body, "#EXT-X-STREAM-INF") > 0 then
        for each ln in body.Split(chr(10))
            t = ln.Trim()
            if t <> "" and Left(t, 1) <> "#" then
                vurl = absUrl(url, t)
                vbody = fetchText(vurl, "VARIANT")
                exit for
            end if
        end for
    end if
    try
        probeSegment(vurl, vbody, "VIDEO SEG")
        if audUrl <> "" then
            abody = fetchText(audUrl, "AUDIO PLAYLIST")
            probeSegment(audUrl, abody, "AUDIO SEG")
        end if
    catch e
        print "[PROBE] excecao: " + e.message
    end try
end sub

sub probeSegment(vurl as string, vbody as string, label as string)
    if Left(vbody, 7) <> "#EXTM3U" then
        print "[" + label + "] playlist invalida, pulando"
        return
    end if
    seg = ""
    for each ln in vbody.Split(chr(10))
        t = ln.Trim()
        if t <> "" and Left(t, 1) <> "#" then
            seg = t
            exit for
        end if
    end for
    if seg = "" then
        print "[" + label + "] nenhum segmento na playlist"
        return
    end if
    surl = absUrl(vurl, seg)
    path = "tmp:/probe.ts"
    DeleteFile(path)
    req = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    req.SetMessagePort(port)
    req.SetUrl(surl)
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.InitClientCertificates()
    print "[" + label + "] GET " + surl
    if not req.AsyncGetToFile(path) then
        print "[" + label + "] nao foi possivel iniciar download"
        return
    end if
    msg = wait(20000, port)
    if type(msg) <> "roUrlEvent" then
        print "[" + label + "] TIMEOUT"
        return
    end if
    code = msg.GetResponseCode()
    ct = "?"
    h = msg.GetResponseHeaders()
    if h <> invalid and h["content-type"] <> invalid then ct = h["content-type"]
    print "[" + label + "] http=" + code.ToStr() + " content-type=" + ct
    if code <> 200 then return
    ba = CreateObject("roByteArray")
    if ba.ReadFile(path) then
        print "[" + label + "] analise do TS:"
        analyzeTs(ba)
    end if
end sub

sub analyzeTs(ba as object)
    n = ba.Count()
    print "[PROBE TS] bytes=" + n.ToStr() + " primeiro byte=" + ba[0].ToStr() + " (esperado 71 = 0x47)"
    pmtPid = -1
    maxPk = n \ 188
    if maxPk > 300 then maxPk = 300
    for i = 0 to maxPk - 1
        o = i * 188
        if ba[o] <> 71 then
            print "[PROBE TS] perdeu sincronismo no pacote " + i.ToStr()
            return
        end if
        pid = ((ba[o + 1] and 31) * 256) + ba[o + 2]
        pusi = (ba[o + 1] and 64) <> 0
        if pusi and (pid = 0 or pid = pmtPid) then
            p = o + 4
            if (ba[o + 3] and 32) <> 0 then p = p + 1 + ba[o + 4]
            p = p + 1 + ba[p]
            slen = ((ba[p + 1] and 15) * 256) + ba[p + 2]
            endq = p + 3 + slen - 4
            if pid = 0 and pmtPid < 0 then
                q = p + 8
                while q + 3 < endq
                    if ((ba[q] * 256) + ba[q + 1]) <> 0 then
                        pmtPid = ((ba[q + 2] and 31) * 256) + ba[q + 3]
                        exit while
                    end if
                    q = q + 4
                end while
                print "[PROBE TS] PMT pid=" + pmtPid.ToStr()
            else if pid = pmtPid then
                pil = ((ba[p + 10] and 15) * 256) + ba[p + 11]
                q = p + 12 + pil
                while q + 4 < endq
                    st = ba[q]
                    epid = ((ba[q + 1] and 31) * 256) + ba[q + 2]
                    il = ((ba[q + 3] and 15) * 256) + ba[q + 4]
                    print "[PROBE TS] stream_type=0x" + StrI(st, 16).Trim() + " pid=" + epid.ToStr() + "  " + tsName(st)
                    q = q + 5 + il
                end while
                return
            end if
        end if
    end for
    print "[PROBE TS] PMT nao encontrada nos primeiros pacotes"
end sub

function tsName(st as integer) as string
    if st = 27 then return "H.264 (video)"
    if st = 36 then return "H.265/HEVC (video)"
    if st = 2 then return "MPEG-2 (video)"
    if st = 15 then return "AAC ADTS (audio)"
    if st = 17 then return "AAC LATM (audio)"
    if st = 3 or st = 4 then return "MPEG (audio)"
    if st = 129 then return "AC-3 (audio)"
    if st = 135 then return "E-AC-3 (audio)"
    if st = 21 then return "metadata ID3"
    if st = 6 then return "private data (AC-3/legenda?)"
    return "desconhecido"
end function

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
