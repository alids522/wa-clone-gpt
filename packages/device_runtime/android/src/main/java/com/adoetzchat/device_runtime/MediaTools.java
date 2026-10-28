package com.adoetzchat.device_runtime;

import android.content.Context;
import android.content.ContentValues;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import java.io.*;
import java.util.HashMap;
import java.util.Map;

final class MediaTools {
    static String safeName(String value) {
        String name=value==null?"Lampiran":value.replace('/', '_').replace((char)92,'_').replaceAll("\\p{Cntrl}","_");
        name=name.substring(0,Math.min(name.length(),200));
        return name.isEmpty() || name.equals(".") || name.equals("..")?"Lampiran":name;
    }
    static File privateFile(Context context, String path) throws IOException {
        File file=new File(path).getCanonicalFile();
        String root=context.getApplicationInfo().dataDir;
        if (!file.isFile() || !file.getPath().startsWith(new File(root).getCanonicalPath()+File.separator))
            throw new IOException("File aplikasi tidak tersedia");
        return file;
    }
    static Map<String,Object> preview(File file, String mime) throws Exception {
        Map<String,Object> output=new HashMap<>();
        Bitmap bitmap=null;
        if (mime.startsWith("video/")) {
            try (MediaMetadataRetriever reader=new MediaMetadataRetriever()) {
                reader.setDataSource(file.getPath());
                String duration=reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
                if(duration!=null) output.put("duration",Long.parseLong(duration));
                bitmap=reader.getScaledFrameAtTime(0,MediaMetadataRetriever.OPTION_CLOSEST_SYNC,320,320);
            }
        } else if (mime.startsWith("image/")) {
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
            BitmapFactory.decodeFile(file.getPath(),bounds);
            if(bounds.outWidth<=0 || bounds.outHeight<=0) return output;
            output.put("width",bounds.outWidth);output.put("height",bounds.outHeight);
            BitmapFactory.Options sample=new BitmapFactory.Options();sample.inSampleSize=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/sample.inSampleSize>640) {
                sample.inSampleSize=sample.inSampleSize<=1?2:sample.inSampleSize*2;
            }
            bitmap=BitmapFactory.decodeFile(file.getPath(),sample);
            if(bitmap!=null) try {
                int orientation=new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);
                Matrix matrix=new Matrix();
                switch(orientation) {
                    case 2: matrix.setScale(-1,1);break;
                    case 3: matrix.setRotate(180);break;
                    case 4: matrix.setScale(1,-1);break;
                    case 5: matrix.setRotate(90);matrix.postScale(-1,1);break;
                    case 6: matrix.setRotate(90);break;
                    case 7: matrix.setRotate(270);matrix.postScale(-1,1);break;
                    case 8: matrix.setRotate(270);break;
                }
                Bitmap rotated=Bitmap.createBitmap(bitmap,0,0,bitmap.getWidth(),bitmap.getHeight(),matrix,true);
                if(rotated!=bitmap) {bitmap.recycle();bitmap=rotated;}
            } catch(IOException ignored) {}
        }
        if(bitmap!=null) {
            try {
                double scale=Math.min(1,320.0/Math.max(bitmap.getWidth(),bitmap.getHeight()));
                Bitmap small=Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bitmap.getWidth()*scale)),Math.max(1,(int)(bitmap.getHeight()*scale)),true);
                if(small!=bitmap){bitmap.recycle();bitmap=small;}
                ByteArrayOutputStream stream=new ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.JPEG,60,stream);
                while(stream.size()>16000 && bitmap.getWidth()>48 && bitmap.getHeight()>48) {
                    small=Bitmap.createScaledBitmap(bitmap,Math.max(1,bitmap.getWidth()*3/4),Math.max(1,bitmap.getHeight()*3/4),true);
                    bitmap.recycle();bitmap=small;stream.reset();bitmap.compress(Bitmap.CompressFormat.JPEG,55,stream);
                }
                if(stream.size()<=16000) output.put("thumbnail",Base64.encodeToString(stream.toByteArray(),Base64.NO_WRAP));
            } finally {bitmap.recycle();}
        }
        return output;
    }
    static void copy(Context context, File file, Uri uri) throws IOException {
        try (InputStream in=new FileInputStream(file);OutputStream out=context.getContentResolver().openOutputStream(uri,"w")) {
            if(out==null) throw new IOException("Penyimpanan tidak tersedia");
            byte[] buffer=new byte[65536];int n;
            while((n=in.read(buffer))!=-1) out.write(buffer,0,n);
            out.flush();
        }
    }
    static String save(Context context, File file, String name, String mime) throws IOException {
        boolean image=mime.startsWith("image/"),video=mime.startsWith("video/");
        Uri collection=image?MediaStore.Images.Media.EXTERNAL_CONTENT_URI:video?MediaStore.Video.Media.EXTERNAL_CONTENT_URI:MediaStore.Downloads.EXTERNAL_CONTENT_URI;
        ContentValues values=new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME,name);
        values.put(MediaStore.MediaColumns.MIME_TYPE,mime);
        values.put(MediaStore.MediaColumns.RELATIVE_PATH,(image?Environment.DIRECTORY_PICTURES:video?Environment.DIRECTORY_MOVIES:Environment.DIRECTORY_DOWNLOADS)+"/Adoetz Chat");
        values.put(MediaStore.MediaColumns.IS_PENDING,1);
        Uri uri=context.getContentResolver().insert(collection,values);
        if(uri==null) throw new IOException("Penyimpanan tidak tersedia");
        try {
            copy(context,file,uri);
            values.clear();values.put(MediaStore.MediaColumns.IS_PENDING,0);
            context.getContentResolver().update(uri,values,null,null);
            return uri.toString();
        } catch(IOException|RuntimeException e) {context.getContentResolver().delete(uri,null,null);throw e;}
    }
}
