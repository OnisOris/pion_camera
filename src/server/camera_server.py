import gi

gi.require_version("Gst", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import GLib, Gst, GstRtspServer


class PioServer:
    def __init__(self):
        self.server = GstRtspServer.RTSPServer()
        self.factory = GstRtspServer.RTSPMediaFactory()
        self.factory.set_launch(
            "( v4l2src device=/dev/video0 ! videoconvert ! videoscale ! video/x-raw,width=640,height=480 ! "
            "x264enc tune=zerolatency bitrate=5000 speed-preset=ultrafast ! "
            "rtph264pay config-interval=1 name=pay0 pt=96 )"
        )
        self.factory.set_shared(True)
        self.server.get_mount_points().add_factory(
            "/pioneer_stream", self.factory
        )
        self.server.attach(None)


def main():
    Gst.init(None)
    pioserver = PioServer()
    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
