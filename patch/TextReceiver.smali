.class public Lcom/anonym/bridge/TextReceiver;
.super Landroid/content/BroadcastReceiver;


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V

    return-void
.end method


# virtual methods
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
    .locals 5

    invoke-static {}, Lcom/anonym/bridge/Native;->ensure()V

    # action == com.anonym.alicebridge.START_VOICE -> start voice dialog
    invoke-virtual {p2}, Landroid/content/Intent;->getAction()Ljava/lang/String;

    move-result-object v0

    const-string v1, "com.anonym.alicebridge.START_VOICE"

    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-eqz v1, :text

    sget-object v2, Lru/yandex/io/sdk/BridgeHolder;->sdk:Lru/yandex/io/sdk/jni/YandexIOSDK;

    if-nez v2, :conv

    const-string v3, "AliceBridge"

    const-string v4, "sdk is null"

    invoke-static {v3, v4}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    return-void

    :conv
    invoke-virtual {v2}, Lru/yandex/io/sdk/jni/YandexIOSDK;->startConversation()V

    return-void

    :text
    const-string v0, "text"

    invoke-virtual {p2, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    if-nez v0, :cond_0

    return-void

    :cond_0
    sget-object v1, Lru/yandex/io/sdk/BridgeHolder;->sdk:Lru/yandex/io/sdk/jni/YandexIOSDK;

    if-nez v1, :cond_1

    const-string v2, "AliceBridge"

    const-string v3, "sdk is null"

    invoke-static {v2, v3}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    return-void

    :cond_1
    const/4 v2, 0x0

    const/4 v3, 0x0

    invoke-virtual {v1, v0, v2, v3}, Lru/yandex/io/sdk/jni/YandexIOSDK;->sendTextQuery(Ljava/lang/String;Lru/yandex/io/sdk/jni/JniAliceRequestCallback;Z)V

    return-void
.end method
