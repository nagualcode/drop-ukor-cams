function CamsUrl() as string
    return "https://droptv.com.br/cam/cams.json"
end function

function DebugOn() as boolean
    return true
end function

sub dlog(msg as string)
    print "[DropCams " + CreateObject("roDateTime").ToISOString() + "] " + msg
end sub

sub init()
    m.list = m.top.findNode("list")
    m.title = m.top.findNode("title")
    m.video = m.top.findNode("video")
    m.snapA = m.top.findNode("snapA")
    m.snapB = m.top.findNode("snapB")
    m.front = m.snapA
    m.back = m.snapB
    m.status = m.top.findNode("status")
    m.statusBg = m.top.findNode("statusBg")
    m.timer = m.top.findNode("refreshTimer")
    m.loadClock = CreateObject("roTimespan")
    m.cams = []
    m.playing = false
    m.loading = false
    m.n = 0
    m.snapUrl = ""
    m.curCam = invalid
    m.curLive = true
    m.attempt = 1
    m.segCount = 0

    m.list.observeField("itemSelected", "onItemSelected")
    m.video.observeField("state", "onVideoState")
    m.video.observeField("streamInfo", "onStreamInfo")
    m.video.observeField("downloadedSegment", "onSegment")
    m.snapA.observeField("loadStatus", "onSnapStatus")
    m.snapB.observeField("loadStatus", "onSnapStatus")
    m.timer.observeField("fire", "onTimer")

    dlog("app iniciado. cams.json = " + CamsUrl())
    loadCams()
end sub

sub setStatus(t as string)
    m.status.text = t
    m.statusBg.visible = (t <> "")
end sub

sub showUI(b as boolean)
    m.list.visible = b
    m.title.visible = b
end sub

' ---------- lista ----------
sub loadCams()
    setStatus("Carregando cameras...")
    m.task = CreateObject("roSGNode", "FetchTask")
    m.task.url = CamsUrl()
    m.task.observeField("result", "onCamsLoaded")
    m.task.observeField("error", "onCamsError")
    m.task.control = "RUN"
end sub

sub onCamsError()
    dlog("erro ao baixar cams.json: " + m.task.error)
    setStatus("Erro: " + m.task.error + "  (* para tentar de novo)")
    m.list.setFocus(true)
end sub

sub onCamsLoaded()
    cams = m.task.result.cams
    if type(cams) <> "roArray" or cams.Count() = 0 then
        setStatus("Nenhuma camera no JSON")
        return
    end if
    m.cams = cams
    dlog("cams.json ok: " + cams.Count().ToStr() + " cameras")
    content = CreateObject("roSGNode", "ContentNode")
    for each cam in cams
        node = content.CreateChild("ContentNode")
        node.title = cam.lookup("name")
    end for
    m.list.content = content
    m.list.setFocus(true)
    setStatus(cams.Count().ToStr() + " cameras  |  * = recarregar lista")
end sub

sub onItemSelected()
    cam = m.cams[m.list.itemSelected]
    if cam = invalid then return
    startCam(cam)
end sub

function camType(cam as object) as string
    t = cam.lookup("type")
    if t <> invalid then return LCase(t)
    if Instr(1, LCase(cam.lookup("url")), ".m3u8") > 0 then return "hls"
    return "jpg"
end function

function bust(url as string) as string
    m.n = m.n + 1
    sep = "?"
    if Instr(1, url, "?") > 0 then sep = "&"
    return url + sep + "_t=" + m.n.ToStr()
end function

sub startCam(cam as object)
    m.playing = true
    m.curCam = cam
    m.attempt = 1
    m.segCount = 0
    dlog("abrindo '" + cam.lookup("name") + "' tipo=" + camType(cam))
    showUI(false)
    setStatus("Carregando " + cam.lookup("name") + "...")

    if camType(cam) = "hls" then
        live = cam.lookup("live")
        if live = invalid then live = true
        m.curLive = live
        if DebugOn() then
            m.probe = CreateObject("roSGNode", "PlaylistProbe")
            m.probe.url = cam.lookup("url")
            m.probe.control = "RUN"
        end if
        playHls(cam, m.curLive)
    else
        ms = cam.lookup("refresh")
        if ms = invalid then ms = 1000
        if ms < 500 then ms = 500
        m.snapUrl = cam.lookup("url")
        m.front = m.snapA
        m.back = m.snapB
        m.snapA.uri = ""
        m.snapB.uri = ""
        m.snapA.opacity = 1
        m.snapB.opacity = 0
        m.loading = false
        requestFrame()
        m.timer.duration = ms / 1000
        m.timer.control = "start"
        m.top.setFocus(true)
    end if
end sub

' ---------- HLS ----------
sub playHls(cam as object, live as boolean)
    c = CreateObject("roSGNode", "ContentNode")
    c.url = cam.lookup("url")
    c.title = cam.lookup("name")
    c.streamFormat = "hls"
    c.live = live
    c.HttpCertificatesFile = "common:/certs/ca-bundle.crt"
    c.HttpSendClientCertificates = true
    hdrs = cam.lookup("headers")
    if type(hdrs) = "roArray" then c.HttpHeaders = hdrs
    dlog("HLS tentativa " + m.attempt.ToStr() + " live=" + iif(live, "true", "false"))
    m.video.control = "stop"
    m.video.content = c
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
end sub

function iif(c as boolean, a as string, b as string) as string
    if c then return a
    return b
end function

sub onVideoState()
    s = m.video.state
    dlog("video state=" + s)
    if s = "playing" then
        setStatus("")
    else if s = "buffering" then
        setStatus("Carregando...")
    else if s = "error" then
        dlog("ERRO code=" + m.video.errorCode.ToStr() + " msg=" + m.video.errorMsg + " str=" + m.video.errorStr)
        dlog("ERRO info=" + FormatJson(m.video.errorInfo))
        if m.attempt = 1 and m.curCam <> invalid then
            m.attempt = 2
            m.curLive = not m.curLive
            playHls(m.curCam, m.curLive)
        else
            setStatus("Erro HLS " + m.video.errorCode.ToStr() + ": " + m.video.errorMsg + "  (Voltar para sair)")
        end if
    end if
end sub

sub onStreamInfo()
    dlog("streamInfo=" + FormatJson(m.video.streamInfo))
end sub

sub onSegment()
    m.segCount = m.segCount + 1
    if m.segCount <= 3 then dlog("segmento #" + m.segCount.ToStr() + " " + FormatJson(m.video.downloadedSegment))
end sub

' ---------- JPEG (double buffer) ----------
sub requestFrame()
    if m.loading then return
    m.loading = true
    m.loadClock.Mark()
    m.back.uri = bust(m.snapUrl)
end sub

sub onSnapStatus(event as object)
    node = event.getRoSGNode()
    if not m.playing then return
    if node.id <> m.back.id then return
    st = node.loadStatus
    if st = "ready" then
        node.opacity = 1
        m.front.opacity = 0
        tmp = m.front
        m.front = m.back
        m.back = tmp
        m.loading = false
        setStatus("")
        if DebugOn() then dlog("quadro ok em " + m.loadClock.TotalMilliseconds().ToStr() + " ms")
    else if st = "failed" then
        m.loading = false
        dlog("quadro FALHOU: " + node.uri)
        setStatus("Falha ao carregar imagem (mantendo ultimo quadro)")
    end if
end sub

sub onTimer()
    if not m.playing or m.snapUrl = "" then return
    if m.loading and m.loadClock.TotalMilliseconds() > 8000 then
        dlog("timeout de quadro, tentando de novo")
        m.loading = false
    end if
    requestFrame()
end sub

' ---------- saida ----------
sub stopPlayback()
    dlog("parando reproducao")
    m.playing = false
    m.timer.control = "stop"
    m.video.control = "stop"
    m.video.visible = false
    m.snapA.uri = ""
    m.snapB.uri = ""
    m.snapA.opacity = 1
    m.snapB.opacity = 0
    m.front = m.snapA
    m.back = m.snapB
    m.snapUrl = ""
    m.loading = false
    showUI(true)
    setStatus(m.cams.Count().ToStr() + " cameras  |  * = recarregar lista")
    m.list.setFocus(true)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "back" and m.playing then
        stopPlayback()
        return true
    else if key = "options" and not m.playing then
        loadCams()
        return true
    end if
    return false
end function
