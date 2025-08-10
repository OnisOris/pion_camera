import socket
from abc import ABC, abstractmethod
from typing import Optional

import cv2
import numpy as np
from numpy.typing import NDArray


# Абстрактный базовый класс для камеры
class BaseCamera(ABC):
    @abstractmethod
    def get_cv_frame(self) -> Optional[NDArray]:
        """
        Должен возвращать кадр в формате cv2 или None, если кадр не получен.
        """
        pass


# Реализация для RTSP камеры
class RTSPCamera(BaseCamera):
    def __init__(self, rtsp_url: str):
        self.rtsp_url = rtsp_url
        self.cap = cv2.VideoCapture(self.rtsp_url)

    def get_cv_frame(self) -> Optional[NDArray]:
        if not self.cap.isOpened():
            self.cap.open(self.rtsp_url)
        ret, frame = self.cap.read()
        if ret:
            return frame
        else:
            return None

    def release(self):
        if self.cap.isOpened():
            self.cap.release()


class SocketCamera(BaseCamera):
    def __init__(
        self,
        ip: str,
        port: int,
        timeout: float = 0.5,
        video_buffer_size: int = 65000,
        log_connection: bool = True,
    ):
        self.ip = ip
        self.port = port
        self.timeout = timeout
        self.video_buffer_size = video_buffer_size
        self.log_connection = log_connection
        self.tcp = None
        self.udp = None
        self.connected = False
        self._video_frame_buffer = bytes()

    def new_tcp(self) -> socket.socket:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(self.timeout)
        return sock

    def new_udp(self) -> socket.socket:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.settimeout(self.timeout)
        return sock

    def connect(self) -> None:
        self.disconnect()
        self.tcp = self.new_tcp()
        self.udp = self.new_udp()
        try:
            self.tcp.connect((self.ip, self.port))
            self.udp.bind(self.tcp.getsockname())
            self.connected = True
            if self.log_connection:
                print("SocketCamera CONNECTED")
        except Exception as e:
            if self.log_connection:
                print("SocketCamera connection failed:", e)
            self.connected = False

    def disconnect(self) -> None:
        self.connected = False
        if self.tcp:
            self.tcp.close()
            self.tcp = None
        if self.udp:
            self.udp.close()
            self.udp = None

    def get_frame(self) -> Optional[bytes]:
        try:
            if not self.connected:
                self.connect()
            self._video_frame_buffer, addr = self.udp.recvfrom(
                self.video_buffer_size
            )
            beginning = self._video_frame_buffer.find(b"\xff\xd8")
            if beginning == -1:
                return None
            self._video_frame_buffer = self._video_frame_buffer[beginning:]
            end = self._video_frame_buffer.find(b"\xff\xd9")
            if end == -1:
                return None
            return self._video_frame_buffer[: end + 2]
        except Exception as e:
            if self.log_connection:
                print("SocketCamera get_frame error:", e)
            return None

    def get_cv_frame(self) -> Optional[NDArray]:
        frame_bytes = self.get_frame()
        if frame_bytes is not None:
            frame = cv2.imdecode(
                np.frombuffer(frame_bytes, dtype=np.uint8), cv2.IMREAD_COLOR
            )
            return frame
        return None
