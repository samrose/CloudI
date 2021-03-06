//-*-Mode:java;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
// ex: set ft=java fenc=utf-8 sts=4 ts=4 sw=4 et nomod:
//
// BSD LICENSE
// 
// Copyright (c) 2016, Michael Truog <mjtruog at gmail dot com>
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in
//       the documentation and/or other materials provided with the
//       distribution.
//     * All advertising materials mentioning features or use of this
//       software must display the following acknowledgment:
//         This product includes software developed by Michael Truog
//     * The name of the author may not be used to endorse or promote
//       products derived from this software without specific prior
//       written permission
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
// CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
// INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
// BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
// DAMAGE.
//

package org.cloudi;

import com.ericsson.otp.erlang.OtpErlangPid;

public class FunctionObject9 implements FunctionInterface9
{
    private final Function9<Integer,
                            String,
                            String,
                            byte[],
                            byte[],
                            Integer,
                            Byte,
                            byte[],
                            OtpErlangPid> function;

    public FunctionObject9(final Object instance, final String methodName)
        throws NoSuchMethodException
    {
        this.function = new Function9<Integer,
                                      String,
                                      String,
                                      byte[],
                                      byte[],
                                      Integer,
                                      Byte,
                                      byte[],
                                      OtpErlangPid>(instance, methodName);
    }

    public Object invoke(Integer command, String name, String pattern,
                         byte[] request_info, byte[] request,
                         Integer timeout, Byte priority,
                         byte[] trans_id, OtpErlangPid pid)
        throws Throwable
    {
        return this.function.invoke(command, name, pattern,
                                    request_info, request,
                                    timeout, priority,
                                    trans_id, pid);
    }
}

