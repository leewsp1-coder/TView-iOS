import Foundation
import UIKit
import Swifter

/// Tesla 브라우저로 MJPEG 스트림을 서빙하는 HTTP 서버
class StreamingServer {

    static let port: UInt16 = 8080

    private var server: HttpServer
    private let lock = NSLock()

    private var netService: NetService?
    private var _isRunning = false
    private var _currentFrame: Data?
    private var _isDrivingLocked = false

    // HUD 데이터
    private var _currentSpeed: Double = 0
    private var _currentHeading: Double = 0
    private var _cameraDistance: Double = .infinity
    private var _cameraSpeedLimit: Int = 0
    private var _cameraType: String = ""
    private var _cameraAlertLevel: String = "none"

    // 주행 중 잠금 시 보여줄 경고 화면
    private let lockFrame: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 400))
        let image = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 32)
            ]
            let text = "주행 중 잠금"
            let size = text.size(withAttributes: attrs)
            let rect = CGRect(x: (640 - size.width) / 2, y: (400 - size.height) / 2,
                              width: size.width, height: size.height)
            text.draw(in: rect, withAttributes: attrs)
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }()

    init() {
        server = HttpServer()
        setupRoutes()
    }

    // MARK: - 공개 메서드

    func start() throws {
        lock.lock()
        _isRunning = true
        lock.unlock()
        try server.start(StreamingServer.port, forceIPv4: true)

        // Bonjour 광고 - 로컬 네트워크에서 "tview._http._tcp.local" 로 서비스 발견 가능
        netService = NetService(domain: "local.", type: "_http._tcp.", name: "tview",
                                port: Int32(StreamingServer.port))
        netService?.publish()
    }

    func stop() {
        netService?.stop()
        netService = nil
        lock.lock()
        _isRunning = false
        lock.unlock()
        server.stop()
    }

    /// 기기의 mDNS 로컬 호스트명 (예: LeewanseoksIphone.local)
    static var localHostname: String {
        let host = ProcessInfo.processInfo.hostName
        // 시뮬레이터에서는 "localhost" 반환될 수 있음
        if host == "localhost" || host.isEmpty { return "iPhone.local" }
        return host
    }

    /// 새 프레임 업데이트 (백그라운드 스레드에서 호출 가능)
    func updateFrame(_ data: Data) {
        lock.lock()
        _currentFrame = data
        lock.unlock()
    }

    /// 주행 잠금 상태 설정
    func setDrivingLocked(_ locked: Bool) {
        lock.lock()
        _isDrivingLocked = locked
        lock.unlock()
    }

    /// HUD 데이터 업데이트 (속도, 방향, 단속 카메라 정보)
    func updateHUD(speed: Double, heading: Double,
                   cameraDistance: Double = .infinity,
                   cameraSpeedLimit: Int = 0,
                   cameraType: String = "",
                   cameraAlertLevel: String = "none") {
        lock.lock()
        _currentSpeed = speed
        _currentHeading = heading
        _cameraDistance = cameraDistance
        _cameraSpeedLimit = cameraSpeedLimit
        _cameraType = cameraType
        _cameraAlertLevel = cameraAlertLevel
        lock.unlock()
    }

    // MARK: - 라우트 설정

    private func setupRoutes() {
        // Tesla 브라우저에서 접속하는 메인 페이지
        server["/"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            return .ok(.html(self.generateHTML()))
        }

        // MJPEG 스트림 엔드포인트
        server["/stream"] = { [weak self] _ in
            guard let self else { return .internalServerError }

            return HttpResponse.raw(200, "OK", [
                "Content-Type": "multipart/x-mixed-replace; boundary=--tviewframe",
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Pragma": "no-cache",
                "Connection": "keep-alive",
                "Access-Control-Allow-Origin": "*"
            ]) { [weak self] writer in
                guard let self else { return }

                while true {
                    self.lock.lock()
                    let running = self._isRunning
                    let locked = self._isDrivingLocked
                    let frame = self._currentFrame
                    self.lock.unlock()

                    guard running else { break }

                    let jpeg: Data
                    if locked {
                        jpeg = self.lockFrame
                    } else if let f = frame {
                        jpeg = f
                    } else {
                        Thread.sleep(forTimeInterval: 0.033)
                        continue
                    }

                    do {
                        let header = "--tviewframe\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n"
                        try writer.write(Data(header.utf8))
                        try writer.write(jpeg)
                        try writer.write(Data("\r\n".utf8))
                    } catch {
                        break
                    }

                    Thread.sleep(forTimeInterval: 1.0 / 30.0)
                }
            }
        }

        // HUD 데이터 (JSON) - Tesla 페이지에서 1초 간격으로 폴링
        server["/hud"] = { [weak self] _ in
            guard let self else { return .internalServerError }

            self.lock.lock()
            let speed       = self._currentSpeed
            let heading     = self._currentHeading
            let camDist     = self._cameraDistance
            let camLimit    = self._cameraSpeedLimit
            let camType     = self._cameraType
            let alertLevel  = self._cameraAlertLevel
            self.lock.unlock()

            // 방위각 → 방향 문자열
            let dirs = ["북","북동","동","남동","남","남서","서","북서"]
            let hdgText = dirs[((Int((heading / 45).rounded()) % 8) + 8) % 8]

            // 활성 카메라 판단 (alertLevel이 none이 아니고 거리가 유한할 때)
            let isActive = alertLevel != "none" && camDist.isFinite

            // JSONSerialization으로 안전한 JSON 생성 (특수문자 자동 이스케이프)
            var cameraDict: [String: Any] = ["active": isActive]
            if isActive {
                cameraDict["distance"]   = Int(camDist)
                cameraDict["speedLimit"] = camLimit
                cameraDict["type"]       = camType
                cameraDict["level"]      = alertLevel
            }
            let rootDict: [String: Any] = [
                "speed":       Int(speed),
                "heading":     Int(heading),
                "headingText": hdgText,
                "camera":      cameraDict
            ]
            let json = (try? JSONSerialization.data(withJSONObject: rootDict))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

            return HttpResponse.raw(200, "OK", [
                "Content-Type": "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-cache"
            ]) { writer in
                try writer.write(Data(json.utf8))
            }
        }

        // 상태 확인 엔드포인트
        server["/status"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            self.lock.lock()
            let running = self._isRunning
            self.lock.unlock()
            return .ok(.text(running ? "streaming" : "stopped"))
        }
    }

    // MARK: - Tesla 브라우저용 HTML 생성
    // 레이아웃: 전체화면 / 분할(HUD 상단 고정 + 미러 하단) / 자유배치(드래그+크기조절)

    private func generateHTML() -> String {
        return """
        <!DOCTYPE html>
        <html lang="ko">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
        <title>TView</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{width:100%;height:100%;background:#111;overflow:hidden;font-family:-apple-system,sans-serif;-webkit-user-select:none;user-select:none}
        #hud{position:fixed;top:0;left:0;right:0;height:64px;background:rgba(0,0,0,.88);display:flex;align-items:center;padding:0 14px;z-index:100;border-bottom:1px solid rgba(255,255,255,.08);gap:0}
        #sp-wrap{display:flex;align-items:baseline;gap:4px;min-width:88px}
        #sp-val{font-size:42px;font-weight:700;color:#fff;line-height:1;transition:color .3s}
        #sp-val.over{color:#ff3b30}
        #sp-unit{font-size:12px;color:rgba(255,255,255,.5)}
        #cam-wrap{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px}
        #cam-badge{font-size:12px;font-weight:600;padding:3px 10px;border-radius:12px;display:none;white-space:nowrap}
        #cam-badge.caution{display:block;background:rgba(255,204,0,.18);color:#ffcc00;border:1px solid rgba(255,204,0,.35)}
        #cam-badge.warning{display:block;background:rgba(255,149,0,.18);color:#fa6400;border:1px solid rgba(255,149,0,.35)}
        #cam-badge.alert{display:block;background:rgba(255,59,48,.18);color:#ff3b30;border:1px solid rgba(255,59,48,.35);animation:blink .5s ease-in-out infinite alternate}
        @keyframes blink{from{background:rgba(255,59,48,.08)}to{background:rgba(255,59,48,.42)}}
        #cam-sub{font-size:10px;color:rgba(255,255,255,.35);display:none}
        #cam-sub.show{display:block}
        #hdg-wrap{display:flex;flex-direction:column;align-items:flex-end;min-width:52px}
        #hdg-num{font-size:20px;font-weight:700;color:rgba(255,255,255,.9)}
        #hdg-dir{font-size:10px;color:rgba(255,255,255,.4)}
        #toolbar{position:fixed;top:72px;right:10px;display:flex;flex-direction:column;gap:5px;z-index:99}
        .lb{width:42px;height:30px;background:rgba(28,28,30,.92);border:1px solid rgba(255,255,255,.12);border-radius:7px;color:rgba(255,255,255,.7);font-size:10px;cursor:pointer;display:flex;align-items:center;justify-content:center}
        .lb.on{background:rgba(10,132,255,.32);border-color:rgba(10,132,255,.55);color:#7dd3fc}
        #panel{position:fixed;background:#000;border-radius:6px;overflow:hidden;touch-action:none;z-index:50;border:1px solid rgba(255,255,255,.08)}
        #panel.full{top:0!important;left:0!important;width:100vw!important;height:100vh!important;border-radius:0!important;border:none!important}
        #panel.split{top:64px!important;left:0!important;width:100vw!important;height:calc(100vh - 64px)!important;border-radius:0!important;border:none!important;border-top:1px solid rgba(255,255,255,.08)!important}
        #mimg{width:100%;height:100%;object-fit:contain;display:block;pointer-events:none}
        #dbar{position:absolute;top:0;left:0;right:24px;height:20px;cursor:move;z-index:5;background:linear-gradient(to bottom,rgba(255,255,255,.07),transparent)}
        #rszh{position:absolute;bottom:0;right:0;width:22px;height:22px;cursor:se-resize;z-index:5;background:linear-gradient(135deg,transparent 55%,rgba(255,255,255,.28) 55%)}
        #panel.full #dbar,#panel.split #dbar,#panel.full #rszh,#panel.split #rszh{display:none!important}
        #rconn{position:absolute;inset:0;background:rgba(0,0,0,.8);display:none;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:#fff;font-size:14px;z-index:9}
        #rconn.show{display:flex}
        .spin{width:26px;height:26px;border:2.5px solid rgba(255,255,255,.2);border-top-color:#fff;border-radius:50%;animation:spin .8s linear infinite}
        @keyframes spin{to{transform:rotate(360deg)}}
        #stopped{position:absolute;inset:0;background:rgba(0,0,0,.88);display:none;flex-direction:column;align-items:center;justify-content:center;gap:12px;z-index:8}
        #stopped.show{display:flex}
        #stopped .st-icon{font-size:52px}
        #stopped .st-msg{font-size:18px;font-weight:700;color:#fff}
        #stopped .st-sub{font-size:12px;color:rgba(255,255,255,.55);text-align:center;line-height:1.6;padding:0 20px}
        </style>
        </head>
        <body>
        <div id="hud">
          <div id="sp-wrap"><span id="sp-val">--</span><span id="sp-unit">km/h</span></div>
          <div id="cam-wrap"><div id="cam-badge"></div><div id="cam-sub"></div></div>
          <div id="hdg-wrap"><div id="hdg-num">--</div><div id="hdg-dir">--</div></div>
        </div>
        <div id="toolbar">
          <button class="lb" id="bf">전체</button>
          <button class="lb on" id="bs">분할</button>
          <button class="lb" id="bfr">자유</button>
        </div>
        <div id="panel" class="split">
          <div id="dbar"></div>
          <img id="mimg" src="/stream" alt="">
          <div id="rszh"></div>
          <div id="stopped">
            <div class="st-icon">📵</div>
            <div class="st-msg">미러링 중지됨</div>
            <div class="st-sub">iPhone에서 화면 공유를 다시 시작하세요<br>(전체 화면 미러링 버튼 탭)</div>
          </div>
          <div id="rconn"><div class="spin"></div><div>재연결 중...</div></div>
        </div>
        <script>
        var panel=document.getElementById('panel'),
            mimg=document.getElementById('mimg'),
            rconn=document.getElementById('rconn'),
            spVal=document.getElementById('sp-val'),
            camBadge=document.getElementById('cam-badge'),
            camSub=document.getElementById('cam-sub'),
            hdgNum=document.getElementById('hdg-num'),
            hdgDir=document.getElementById('hdg-dir'),
            dbar=document.getElementById('dbar'),
            rszh=document.getElementById('rszh');
        var DIRS=['북','북동','동','남동','남','남서','서','북서'];
        function toDir(h){return DIRS[Math.round(h/45)%8];}
        var layout=localStorage.getItem('tv-layout')||'split';
        var panX=parseFloat(localStorage.getItem('tv-x'))||20;
        var panY=parseFloat(localStorage.getItem('tv-y'))||70;
        var panW=parseFloat(localStorage.getItem('tv-w'))||400;
        var panH=parseFloat(localStorage.getItem('tv-h'))||280;
        function applyLayout(l){
          layout=l; localStorage.setItem('tv-layout',l);
          panel.className='';
          document.querySelectorAll('.lb').forEach(function(b){b.classList.remove('on');});
          if(l==='full'){
            panel.classList.add('full'); document.getElementById('bf').classList.add('on');
          } else if(l==='split'){
            panel.classList.add('split'); panel.removeAttribute('style'); document.getElementById('bs').classList.add('on');
          } else {
            document.getElementById('bfr').classList.add('on');
            panel.style.left=panX+'px'; panel.style.top=panY+'px';
            panel.style.width=panW+'px'; panel.style.height=panH+'px';
          }
        }
        document.getElementById('bf').onclick=function(){applyLayout('full');};
        document.getElementById('bs').onclick=function(){applyLayout('split');};
        document.getElementById('bfr').onclick=function(){applyLayout('free');};
        applyLayout(layout);
        var drg=false,dx0,dy0,dl0,dt0;
        function drStart(cx,cy){if(layout!=='free')return;drg=true;dx0=cx;dy0=cy;dl0=panel.offsetLeft;dt0=panel.offsetTop;}
        function drMove(cx,cy){if(!drg)return;panX=Math.max(0,dl0+(cx-dx0));panY=Math.max(0,dt0+(cy-dy0));panel.style.left=panX+'px';panel.style.top=panY+'px';}
        function drEnd(){if(drg){drg=false;localStorage.setItem('tv-x',panX);localStorage.setItem('tv-y',panY);}}
        dbar.addEventListener('mousedown',function(e){drStart(e.clientX,e.clientY);e.preventDefault();});
        dbar.addEventListener('touchstart',function(e){drStart(e.touches[0].clientX,e.touches[0].clientY);e.preventDefault();},{passive:false});
        window.addEventListener('mousemove',function(e){drMove(e.clientX,e.clientY);});
        window.addEventListener('touchmove',function(e){if(drg){drMove(e.touches[0].clientX,e.touches[0].clientY);e.preventDefault();}},{passive:false});
        window.addEventListener('mouseup',drEnd); window.addEventListener('touchend',drEnd);
        var rzg=false,rx0,ry0,rw0,rh0;
        function rzStart(cx,cy){if(layout!=='free')return;rzg=true;rx0=cx;ry0=cy;rw0=panel.offsetWidth;rh0=panel.offsetHeight;}
        function rzMove(cx,cy){if(!rzg)return;panW=Math.max(160,rw0+(cx-rx0));panH=Math.max(120,rh0+(cy-ry0));panel.style.width=panW+'px';panel.style.height=panH+'px';}
        function rzEnd(){if(rzg){rzg=false;localStorage.setItem('tv-w',panW);localStorage.setItem('tv-h',panH);}}
        rszh.addEventListener('mousedown',function(e){rzStart(e.clientX,e.clientY);e.preventDefault();e.stopPropagation();});
        rszh.addEventListener('touchstart',function(e){rzStart(e.touches[0].clientX,e.touches[0].clientY);e.preventDefault();e.stopPropagation();},{passive:false});
        window.addEventListener('mousemove',function(e){rzMove(e.clientX,e.clientY);});
        window.addEventListener('touchmove',function(e){if(rzg){rzMove(e.touches[0].clientX,e.touches[0].clientY);e.preventDefault();}},{passive:false});
        window.addEventListener('mouseup',rzEnd); window.addEventListener('touchend',rzEnd);
        var stoppedOv=document.getElementById('stopped');
        // 마지막 프레임 수신 시각 추적 → 5초 이상 없으면 중지 오버레이 표시
        var lastFrameMs=Date.now();
        mimg.onload=function(){lastFrameMs=Date.now();stoppedOv.classList.remove('show');};
        setInterval(function(){
          if(Date.now()-lastFrameMs>5000){stoppedOv.classList.add('show');}
          else{stoppedOv.classList.remove('show');}
        },1500);
        var rcTimer=null;
        mimg.onerror=function(){
          if(rcTimer)return;
          rconn.classList.add('show');
          rcTimer=setTimeout(function(){mimg.src='/stream?'+Date.now();rconn.classList.remove('show');rcTimer=null;},2000);
        };
        function updateHUD(){
          fetch('/hud').then(function(r){return r.json();}).then(function(d){
            var spd=d.speed||0;
            spVal.textContent=spd>0?spd:'--';
            var cam=d.camera;
            if(cam&&cam.active&&spd>cam.speedLimit){spVal.classList.add('over');}else{spVal.classList.remove('over');}
            hdgNum.textContent=Math.round(d.heading||0)+'°';
            hdgDir.textContent=toDir(d.heading||0);
            if(cam&&cam.active){
              var dist=Math.round(cam.distance);
              var distStr=dist>=1000?(dist/1000).toFixed(1)+'km':dist+'m';
              camBadge.textContent='📷 '+cam.type+'  '+cam.speedLimit+'km/h  '+distStr;
              camBadge.className=cam.level;
              camSub.textContent=cam.level==='alert'?'⚠️ 단속구간 진입':'';
              camSub.className=cam.level==='alert'?'show':'';
            } else {
              camBadge.className=''; camBadge.textContent=''; camSub.className='';
            }
          }).catch(function(){});
        }
        setInterval(updateHUD,1000); updateHUD();
        </script>
        </body>
        </html>
        """
    }
}
