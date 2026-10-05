function CamsUrl() as string
    return "https://droptv.com.br/cam/cams.json"
end function

sub init()
    m.list = m.top.findNode("list")
    m.video = m.top.findNode("video")
    m.snap = m.top.findNode("snap")
    m.status = m.top.findNode("status")
    m.timer = m.top.findNode("refreshTimer")
    m.cams = []
    m.playing = false
    m.n = 0
    m.snapUrl = ""

    m.list.observeField("itemSelected", "onItemSelected")
    m.video.observeField("state", "onVideoState")
    m.timer.observeField("fire", "onTimer")
    loadCams()
end sub

sub loadCams()
    m.status.text = "Carregando cameras..."
    m.task = CreateObject("roSGNode", "FetchTask")
    m.task.url = CamsUrl()
    m.task.observeField("result", "onCamsLoaded")
    m.task.observeField("error", "onCamsError")
    m.task.control = "RUN"
end sub

sub onCamsError()
    m.status.text = "Erro: " + m.task.error + "  (* para tentar de novo)"
    m.list.setFocus(true)
end sub

sub onCamsLoaded()
    data = m.task.result
    cams = data.cams
    if type(cams) <> "roArray" or cams.Count() = 0 then
        m.status.text = "Nenhuma camera no JSON"
        return
    end if
    m.cams = cams
    content = CreateObject("roSGNode", "ContentNode")
    for each cam in cams
        node = content.CreateChild("ContentNode")
        node.title = cam.lookup("name")
    end for
    m.list.content = content
    m.list.setFocus(true)
    m.status.text = cams.Count().ToStr() + " cameras  |  * = recarregar lista"
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
    m.status.text = "Carregando " + cam.lookup("name") + "..."
    if camType(cam) = "hls" then
        c = CreateObject("roSGNode", "ContentNode")
        c.url = cam.lookup("url")
        c.streamFormat = "hls"
        c.live = true
        m.video.content = c
        m.video.visible = true
        m.video.setFocus(true)
        m.video.control = "play"
    else
        ms = cam.lookup("refresh")
        if ms = invalid then ms = 1000
        if ms < 500 then ms = 500
        m.snapUrl = cam.lookup("url")
        m.snap.uri = bust(m.snapUrl)
        m.snap.visible = true
        m.timer.duration = ms / 1000
        m.timer.control = "start"
        m.top.setFocus(true)
        m.status.text = ""
    end if
end sub

sub onTimer()
    if m.playing and m.snapUrl <> "" then m.snap.uri = bust(m.snapUrl)
end sub

sub onVideoState()
    s = m.video.state
    if s = "playing" then
        m.status.text = ""
    else if s = "error" then
        m.status.text = "Erro ao reproduzir (Voltar para sair)"
    end if
end sub

sub stopPlayback()
    m.playing = false
    m.timer.control = "stop"
    m.video.control = "stop"
    m.video.visible = false
    m.snap.visible = false
    m.snap.uri = ""
    m.snapUrl = ""
    m.status.text = m.cams.Count().ToStr() + " cameras  |  * = recarregar lista"
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
