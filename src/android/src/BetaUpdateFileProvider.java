package org.cagnulen.qdomyoszwift;

import androidx.core.content.FileProvider;

// personal: the provider of the downloaded beta build (BetaUpdate.java). Its own class rather than
// FileProvider itself: the manifest merger allows one provider element per class name, and the
// support email of upstream declares androidx.core.content.FileProvider already
public class BetaUpdateFileProvider extends FileProvider {
}
